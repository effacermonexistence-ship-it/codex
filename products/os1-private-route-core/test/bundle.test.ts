import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { parsePolicyBundle } from "../src/bundle";

const bundle = {
  schema: 2,
  policy_version: "policy-test-v1",
  executor_contracts: [{ version: "executor-test-v1", sha256: "0".repeat(64) }],
  execution_profiles: {
    codex: {
      standard: { model: "gpt-standard", effort: "medium" },
      efficient: { model: "gpt-efficient", effort: "low" },
      deep: { model: "gpt-deep", effort: "xhigh" },
    },
    claude: {
      standard: { model: "sonnet", effort: "medium" },
      efficient: { model: "haiku", effort: "low" },
      deep: { model: "opus", effort: "xhigh" },
    },
  },
  routing: { version: 1, default_provider: "codex", default_permission_profile: "workspace_write", max_steps: 2, rules: [] },
  revas: {
    version: 1, minimum_output_chars: 10, pass_score: 85, retry_score: 55,
    transient_patterns: [], failure_patterns: [], incomplete_patterns: [],
    mutation_terms: [], exact_reply_terms: [], evidence_terms: [], stop_words: [],
  },
};

describe("private policy bundle", () => {
  const candidatePath = process.env.OS1_POLICY_CANDIDATE;
  if (candidatePath) {
    it("validates the generated private rollout candidate", () => {
      const candidate = parsePolicyBundle(readFileSync(candidatePath, "utf8"));
      expect(candidate.schema).toBe(2);
      expect(candidate.executor_contracts).toHaveLength(1);
      expect(candidate.execution_profiles.codex.deep.effort).toBe("xhigh");
      expect(candidate.execution_profiles.claude.efficient.model).toBe("haiku");
    });
  }
  it("accepts the exact version-pinned policy schema", () => {
    expect(parsePolicyBundle(JSON.stringify(bundle)).policy_version).toBe("policy-test-v1");
    expect(parsePolicyBundle(JSON.stringify(bundle)).executor_contracts).toEqual(bundle.executor_contracts);
  });
  it("supports a bounded contract rollover without accepting arbitrary client contracts", () => {
    const current = {
      ...bundle,
      executor_contracts: [
        bundle.executor_contracts[0],
        { version: "executor-test-v2", sha256: "1".repeat(64) },
      ],
    } as Record<string, unknown>;
    expect(parsePolicyBundle(JSON.stringify(current)).executor_contracts).toHaveLength(2);
    expect(() => parsePolicyBundle(JSON.stringify({
      ...current,
      executor_contracts: Array.from({ length: 5 }, (_, index) => ({
        version: `executor-test-v${index + 1}`,
        sha256: String(index).repeat(64),
      })),
    }))).toThrow();
    expect(() => parsePolicyBundle(JSON.stringify({
      ...current,
      execution_profiles: {
        ...(current.execution_profiles as Record<string, unknown>),
        codex: { standard: { model: "../../escape", effort: "medium" } },
      },
    }))).toThrow();
  });
  it("rejects unknown fields and invalid contract hashes", () => {
    expect(() => parsePolicyBundle(JSON.stringify({ ...bundle, rationale: "leak" }))).toThrow();
    expect(() => parsePolicyBundle(JSON.stringify({ ...bundle, schema: 1 }))).toThrow();
    expect(() => parsePolicyBundle(JSON.stringify({
      ...bundle,
      executor_contracts: [{ version: "executor-test-v1", sha256: "bad" }],
    }))).toThrow();
  });
});
