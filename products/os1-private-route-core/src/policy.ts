export type Provider = "codex" | "claude";
export type ProviderPreference = "auto" | Provider;
export type CapacityPlan = { codex: number; claude: number };
export type UsageCounts = { codex: number; claude: number };
export type PermissionProfile = "read_only" | "workspace_write" | "full_access";
export type Action = "agent_run" | "agent_run_efficient" | "agent_run_deep";
export type Step = {
  provider: Provider;
  fallback_provider: Provider;
  permission_profile: PermissionProfile;
  max_steps: number;
  budget_protected: boolean;
};
type Rule = Step & { terms: string[] };
export type Policy = {
  version: 1;
  default_provider: Provider;
  default_permission_profile: PermissionProfile;
  max_steps: number;
  rules: Rule[];
};

const explicitProviderPatterns: ReadonlyArray<readonly [Provider, RegExp]> = [
  ["codex", /(?:^|[\s,:;([{])(?:codex|코덱스|코드엑스)(?=$|[\s,:;.!?\])}]|은|는|이|가|을|를|에|에게|한테|로|와|과)/iu],
  ["claude", /(?:^|[\s,:;([{])(?:claude(?:\s+code)?|클로드(?:\s*코드)?|클라우드\s*코드)(?=$|[\s,:;.!?\])}]|은|는|이|가|을|를|에|에게|한테|로|와|과)/iu],
];

const directedProviderPatterns: ReadonlyArray<readonly [Provider, RegExp[]]> = [
  ["codex", [
    /(?:codex|코덱스|코드엑스)\s*(?:한테|에게|로|으로)\s*[^\n.!?]{0,32}(?:말|시켜|시키|맡겨|맡기|보내|돌려|실행|요청|부탁)/iu,
    /(?:ask|use|run|route|send|delegate)(?:\s+this|\s+it|\s+the\s+task)?\s+(?:to\s+|with\s+)?codex\b/iu,
    /\bcodex\s+(?:should|must|please|can\s+you)\b/iu,
  ]],
  ["claude", [
    /(?:claude(?:\s+code)?|클로드(?:\s*코드)?|클라우드\s*코드)\s*(?:한테|에게|로|으로)\s*[^\n.!?]{0,32}(?:말|시켜|시키|맡겨|맡기|보내|돌려|실행|요청|부탁)/iu,
    /(?:ask|use|run|route|send|delegate)(?:\s+this|\s+it|\s+the\s+task)?\s+(?:to\s+|with\s+)?claude(?:\s+code)?\b/iu,
    /\bclaude(?:\s+code)?\s+(?:should|must|please|can\s+you)\b/iu,
  ]],
];

/**
 * Treat an explicit backend named by the user as a manual selection even when
 * the UI is in Auto mode. Ambiguous mentions of both backends remain governed
 * by RCC policy; only a directed target wins in that case.
 */
export function resolveProviderPreference(
  task: string,
  requested: ProviderPreference,
): ProviderPreference {
  if (requested !== "auto") return requested;
  const normalized = task.normalize("NFKC");
  const directed = directedProviderPatterns.filter(([, patterns]) =>
    patterns.some((pattern) => pattern.test(normalized)),
  ).map(([provider]) => provider);
  if (directed.length === 1) return directed[0];
  if (directed.length > 1) return "auto";

  const mentioned = explicitProviderPatterns.filter(([, pattern]) =>
    pattern.test(normalized),
  ).map(([provider]) => provider);
  return mentioned.length === 1 ? mentioned[0] : "auto";
}

const providers = new Set<Provider>(["codex", "claude"]);
const permissions = new Set<PermissionProfile>([
  "read_only",
  "workspace_write",
  "full_access",
]);

function isProvider(value: unknown): value is Provider {
  return typeof value === "string" && providers.has(value as Provider);
}

function isPermission(value: unknown): value is PermissionProfile {
  return typeof value === "string" && permissions.has(value as PermissionProfile);
}

export function parsePolicy(serialized: string): Policy {
  const value = JSON.parse(serialized) as Record<string, unknown>;
  const policyKeys = Object.keys(value).sort();
  if (policyKeys.join("\n") !== ["default_permission_profile", "default_provider", "max_steps", "rules", "version"].join("\n")) {
    throw new Error("invalid policy");
  }
  if (
    value.version !== 1 ||
    !isProvider(value.default_provider) ||
    !isPermission(value.default_permission_profile) ||
    !Number.isSafeInteger(value.max_steps) ||
    (value.max_steps as number) < 1 ||
    (value.max_steps as number) > 4 ||
    !Array.isArray(value.rules) ||
    value.rules.length > 64
  ) {
    throw new Error("invalid policy");
  }
  const rules: Rule[] = value.rules.map((candidate) => {
    if (typeof candidate !== "object" || candidate === null || Array.isArray(candidate)) {
      throw new Error("invalid policy");
    }
    const rule = candidate as Record<string, unknown>;
    const ruleKeys = Object.keys(rule).sort();
    const required = ["fallback_provider", "max_steps", "permission_profile", "provider", "terms"];
    const optional = [...required, "budget_protected"];
    if (ruleKeys.join("\n") !== required.sort().join("\n") && ruleKeys.join("\n") !== optional.sort().join("\n")) {
      throw new Error("invalid policy");
    }
    if (
      !isProvider(rule.provider) ||
      !isProvider(rule.fallback_provider) ||
      !isPermission(rule.permission_profile) ||
      !Number.isSafeInteger(rule.max_steps) ||
      (rule.max_steps as number) < 1 ||
      (rule.max_steps as number) > 4 ||
      (rule.budget_protected !== undefined && typeof rule.budget_protected !== "boolean") ||
      !Array.isArray(rule.terms) ||
      rule.terms.length === 0 ||
      rule.terms.length > 64 ||
      rule.terms.some((term) => typeof term !== "string" || term.length < 2 || term.length > 128)
    ) {
      throw new Error("invalid policy");
    }
    return {
      provider: rule.provider,
      fallback_provider: rule.fallback_provider,
      permission_profile: rule.permission_profile,
      max_steps: rule.max_steps as number,
      budget_protected: rule.budget_protected !== false,
      terms: rule.terms as string[],
    };
  });
  return {
    version: 1,
    default_provider: value.default_provider,
    default_permission_profile: value.default_permission_profile,
    max_steps: value.max_steps as number,
    rules,
  };
}

export function select(
  policy: Policy,
  task: string,
  preference: ProviderPreference = "auto",
): Step {
  if (preference !== "auto") {
    return {
      provider: preference,
      // A provider selected by the user (either in the UI or in the task text)
      // is a hard target. Retries must not silently run the same request on the
      // other backend and make the session label lie about where it executed.
      fallback_provider: preference,
      permission_profile: policy.default_permission_profile,
      max_steps: policy.max_steps,
      budget_protected: true,
    };
  }
  const folded = task.toLocaleLowerCase("und");
  const containsTerm = (term: string): boolean => {
    const normalized = term.toLocaleLowerCase("und");
    if (!/^[a-z0-9 _-]+$/u.test(normalized)) return folded.includes(normalized);
    const escaped = normalized.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`(^|[^a-z0-9_])${escaped}(?=$|[^a-z0-9_])`, "u").test(folded);
  };
  const rule = policy.rules.find((candidate) =>
    candidate.terms.some(containsTerm),
  );
  if (rule) {
    return {
      provider: rule.provider,
      fallback_provider: rule.fallback_provider,
      permission_profile: rule.permission_profile,
      max_steps: rule.max_steps,
      budget_protected: rule.budget_protected,
    };
  }
  return {
    provider: policy.default_provider,
    fallback_provider: policy.default_provider === "codex" ? "claude" : "codex",
    permission_profile: policy.default_permission_profile,
    max_steps: policy.max_steps,
    budget_protected: false,
  };
}

export function chooseCapacityAware(
  step: Step,
  capacity: CapacityPlan,
  usage: UsageCounts,
): Provider {
  const primary = step.provider;
  const fallback = step.fallback_provider;
  if (capacity[primary] <= 0) return fallback;
  if (capacity[fallback] <= 0 || step.budget_protected) return primary;

  const weightTotal = capacity.codex + capacity.claude;
  const nextTotal = usage.codex + usage.claude + 1;
  const deficit = (provider: Provider): number =>
    (capacity[provider] / weightTotal) * nextTotal - usage[provider];
  const primaryDeficit = deficit(primary);
  const fallbackDeficit = deficit(fallback);
  return primaryDeficit + 0.05 >= fallbackDeficit ? primary : fallback;
}

export function selectAction(
  base: Step,
  selectedProvider: Provider,
  preference: ProviderPreference,
): Action {
  if (preference !== "auto") return "agent_run";
  if (base.budget_protected) return "agent_run_deep";
  if (selectedProvider !== base.provider) return "agent_run_efficient";
  return "agent_run";
}
