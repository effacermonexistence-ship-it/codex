import { describe, expect, it } from "vitest";
import { executionBindingMatches, evaluateArtifact, type Artifact, type RevasPolicy } from "../src/evaluator";

const empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
const policy: RevasPolicy = {
  version: 1, minimum_output_chars: 12, pass_score: 85, retry_score: 55,
  transient_patterns: ["rate limit"], failure_patterns: ["fatal error"], incomplete_patterns: ["remaining work"],
  mutation_terms: ["implement", "code"], exact_reply_terms: ["reply exactly"], evidence_terms: ["tests passed"], stop_words: ["implement"],
};
const base: Artifact = {
  provider: "codex", action: "agent_run", permission_profile: "workspace_write",
  model: "gpt-test", effort: "medium",
  executor_contract_version: "executor-test-v1", executor_contract_sha256: "0".repeat(64),
  exit_code: 0, output: "The requested repository analysis is verified.", stderr: "", workspace_diff_hash: empty,
};

describe("REVAS evaluator", () => {
  it("passes aligned substantive output and exact replies", () => {
    expect(evaluateArtifact("analyze the repository", base, policy).outcome).toBe("pass");
    expect(evaluateArtifact("reply exactly OK", { ...base, output: "OK" }, policy).outcome).toBe("pass");
    expect(evaluateArtifact("reply exactly OK", {
      ...base,
      output: "OK",
      stderr: "optional connector startup error: authentication required",
    }, policy).outcome).toBe("pass");
  });
  it("retries transient failures and incomplete work", () => {
    expect(evaluateArtifact("analyze", { ...base, exit_code: 1, stderr: "rate limit" }, policy).outcome).toBe("retry");
    expect(evaluateArtifact("analyze", { ...base, output: "remaining work" }, policy).outcome).toBe("retry");
  });
  it("requires evidence for mutation tasks and fails fatal output", () => {
    expect(evaluateArtifact("implement the feature", { ...base, output: "done" }, policy).outcome).toBe("retry");
    expect(evaluateArtifact("implement the feature", { ...base, output: "tests passed" }, policy).outcome).toBe("pass");
    expect(evaluateArtifact("analyze", { ...base, output: "fatal error" }, policy).outcome).toBe("fail");
  });
  it("rejects client-side model, effort, permission, and contract substitution", () => {
    const expected = {
      provider: base.provider,
      action: base.action,
      permission_profile: base.permission_profile,
      model: base.model,
      effort: base.effort,
      executor_contract_version: base.executor_contract_version,
      executor_contract_sha256: base.executor_contract_sha256,
    };
    expect(executionBindingMatches(base, expected)).toBe(true);
    expect(executionBindingMatches({ ...base, model: "gpt-other" }, expected)).toBe(false);
    expect(executionBindingMatches({ ...base, effort: "ultra" }, expected)).toBe(false);
    expect(executionBindingMatches({ ...base, permission_profile: "read_only" }, expected)).toBe(false);
    expect(executionBindingMatches({ ...base, executor_contract_sha256: "1".repeat(64) }, expected)).toBe(false);
  });
});
