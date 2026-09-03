import { parsePolicy, type Action, type Policy, type Provider } from "./policy";

const SHA256 = /^[0-9a-f]{64}$/;
const POLICY_KEY = /^os1\/policies\/([0-9a-f]{64})\.json$/;
const CONTRACT_VERSION = /^[A-Za-z0-9._-]{8,96}$/;
const MODEL_IDENTIFIER = /^[A-Za-z0-9][A-Za-z0-9._-]{1,95}$/;
const EFFORTS = new Set(["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]);

export type ExecutionProfile = { model: string; effort: string };
export type ExecutionProfiles = Record<Provider, {
  standard: ExecutionProfile;
  efficient: ExecutionProfile;
  deep: ExecutionProfile;
}>;

export type RevasPolicy = {
  version: 1;
  minimum_output_chars: number;
  pass_score: number;
  retry_score: number;
  transient_patterns: string[];
  failure_patterns: string[];
  incomplete_patterns: string[];
  mutation_terms: string[];
  exact_reply_terms: string[];
  evidence_terms: string[];
  stop_words: string[];
};

export type PolicyBundle = {
  schema: 2;
  policy_version: string;
  executor_contracts: Array<{ version: string; sha256: string }>;
  execution_profiles: ExecutionProfiles;
  routing: Policy;
  revas: RevasPolicy;
};

function exact(value: Record<string, unknown>, keys: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
}

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function boundedList(value: unknown, maximum: number): value is string[] {
  return Array.isArray(value) && value.length <= maximum && value.every(
    (entry) => typeof entry === "string" && entry.length >= 2 && entry.length <= 128,
  );
}

function parseExecutionProfile(value: unknown): ExecutionProfile {
  if (!record(value) || !exact(value, ["model", "effort"]) ||
    typeof value.model !== "string" || !MODEL_IDENTIFIER.test(value.model) ||
    typeof value.effort !== "string" || !EFFORTS.has(value.effort)
  ) throw new Error("invalid policy bundle");
  return { model: value.model, effort: value.effort };
}

export function parseExecutionProfiles(value: unknown): ExecutionProfiles {
  if (!record(value) || !exact(value, ["codex", "claude"])) throw new Error("invalid policy bundle");
  const parseProvider = (candidate: unknown): ExecutionProfiles[Provider] => {
    if (!record(candidate) || !exact(candidate, ["standard", "efficient", "deep"])) {
      throw new Error("invalid policy bundle");
    }
    return {
      standard: parseExecutionProfile(candidate.standard),
      efficient: parseExecutionProfile(candidate.efficient),
      deep: parseExecutionProfile(candidate.deep),
    };
  };
  return { codex: parseProvider(value.codex), claude: parseProvider(value.claude) };
}

export function executionProfileFor(
  profiles: ExecutionProfiles,
  provider: Provider,
  action: Action,
): ExecutionProfile {
  const tier = action === "agent_run_efficient" ? "efficient" : action === "agent_run_deep" ? "deep" : "standard";
  return profiles[provider][tier];
}

function parseRevas(value: unknown): RevasPolicy {
  if (!record(value) || !exact(value, [
    "version", "minimum_output_chars", "pass_score", "retry_score",
    "transient_patterns", "failure_patterns", "incomplete_patterns",
    "mutation_terms", "exact_reply_terms", "evidence_terms", "stop_words",
  ])) throw new Error("invalid policy bundle");
  if (
    value.version !== 1 ||
    !Number.isSafeInteger(value.minimum_output_chars) ||
    (value.minimum_output_chars as number) < 1 || (value.minimum_output_chars as number) > 8_192 ||
    !Number.isSafeInteger(value.pass_score) || (value.pass_score as number) < 1 || (value.pass_score as number) > 100 ||
    !Number.isSafeInteger(value.retry_score) || (value.retry_score as number) < 0 ||
    (value.retry_score as number) >= (value.pass_score as number) ||
    !boundedList(value.transient_patterns, 64) ||
    !boundedList(value.failure_patterns, 64) ||
    !boundedList(value.incomplete_patterns, 64) ||
    !boundedList(value.mutation_terms, 64) ||
    !boundedList(value.exact_reply_terms, 32) ||
    !boundedList(value.evidence_terms, 64) ||
    !boundedList(value.stop_words, 128)
  ) throw new Error("invalid policy bundle");
  return value as RevasPolicy;
}

export function parsePolicyBundle(serialized: string): PolicyBundle {
  const value = JSON.parse(serialized) as unknown;
  if (!record(value) || value.schema !== 2 ||
    typeof value.policy_version !== "string" ||
    value.policy_version.length < 8 || value.policy_version.length > 96
  ) throw new Error("invalid policy bundle");
  const candidates = exact(value, [
    "schema", "policy_version", "executor_contracts", "execution_profiles", "routing", "revas",
  ]) && Array.isArray(value.executor_contracts) ? value.executor_contracts : null;
  if (!candidates || candidates.length < 1 || candidates.length > 4 ||
    candidates.some((candidate) => !record(candidate) ||
      !exact(candidate, ["version", "sha256"]) ||
      typeof candidate.version !== "string" || !CONTRACT_VERSION.test(candidate.version) ||
      typeof candidate.sha256 !== "string" || !SHA256.test(candidate.sha256))
  ) throw new Error("invalid policy bundle");
  const executorContracts = candidates.map((candidate) => ({
    version: String((candidate as Record<string, unknown>).version),
    sha256: String((candidate as Record<string, unknown>).sha256),
  }));
  if (new Set(executorContracts.map((contract) => contract.version)).size !== executorContracts.length ||
    new Set(executorContracts.map((contract) => contract.sha256)).size !== executorContracts.length
  ) throw new Error("invalid policy bundle");
  return {
    schema: 2,
    policy_version: value.policy_version,
    executor_contracts: executorContracts,
    execution_profiles: parseExecutionProfiles(value.execution_profiles),
    routing: parsePolicy(JSON.stringify(value.routing)),
    revas: parseRevas(value.revas),
  };
}

function positiveInteger(value: string): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) throw new Error("invalid policy configuration");
  return parsed;
}

async function sha256Hex(bytes: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function loadPolicyBundle(env: Env): Promise<PolicyBundle> {
  const keyMatch = env.POLICY_BUNDLE_KEY.match(POLICY_KEY);
  if (!keyMatch || keyMatch[1] !== env.POLICY_BUNDLE_SHA256 || !SHA256.test(env.POLICY_BUNDLE_SHA256)) {
    throw new Error("invalid policy configuration");
  }
  const object = await env.POLICY_BUNDLES.get(env.POLICY_BUNDLE_KEY);
  const maximum = positiveInteger(env.MAX_POLICY_BUNDLE_BYTES);
  if (!object || object.size < 2 || object.size > maximum) throw new Error("policy bundle unavailable");
  const bytes = await object.arrayBuffer();
  if (await sha256Hex(bytes) !== env.POLICY_BUNDLE_SHA256) throw new Error("policy bundle integrity failure");
  const serialized = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
  return parsePolicyBundle(serialized);
}
