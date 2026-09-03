import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { parsePolicyBundle } from "../src/bundle";

const bundle = {
  schema: 4,
  policy_version: "policy-test-v1",
  executor_contracts: [{ version: "executor-test-v1", sha256: "0".repeat(64) }],
  execution_profiles: {
    os1_exact: { provider: "local", model: "local-deterministic", effort: "none" },
    cx_fast: { provider: "codex", model: "gpt-efficient", effort: "low" },
    cx_standard: { provider: "codex", model: "gpt-standard", effort: "medium" },
    cl_standard: { provider: "claude", model: "sonnet", effort: "medium" },
    cl_deep: { provider: "claude", model: "opus", effort: "xhigh" },
  },
  maximum_steps: 4,
  rcc: {
    adapter_version: "os1-rcc-adapter-v1",
    policy_sha256: "1".repeat(64),
    engine_sha256: "2".repeat(64),
    authority_sha256: "3".repeat(64),
  },
};

describe("private policy bundle", () => {
  const candidatePath = process.env.OS1_POLICY_CANDIDATE;
  if (candidatePath) {
    it("validates the generated private rollout candidate", () => {
      const candidate = parsePolicyBundle(readFileSync(candidatePath, "utf8"));
      expect(candidate.schema).toBe(4);
      expect(candidate.executor_contracts).toHaveLength(1);
      expect(candidate.execution_profiles.cl_opus_xhigh.effort).toBe("xhigh");
      expect(candidate.execution_profiles.cx_56luna_low.model).toBe("gpt-5.6-luna");
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
        cx_bad: { provider: "codex", model: "../../escape", effort: "medium" },
      },
    }))).toThrow();
  });
  it("rejects unknown fields and invalid contract hashes", () => {
    expect(() => parsePolicyBundle(JSON.stringify({ ...bundle, rationale: "leak" }))).toThrow();
    expect(() => parsePolicyBundle(JSON.stringify({ ...bundle, schema: 3 }))).toThrow();
    expect(() => parsePolicyBundle(JSON.stringify({
      ...bundle,
      executor_contracts: [{ version: "executor-test-v1", sha256: "bad" }],
    }))).toThrow();
  });
});
