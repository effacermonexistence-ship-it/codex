import { describe, expect, it } from "vitest";
import {
  chooseCapacityAware,
  parsePolicy,
  resolveProviderPreference,
  select,
  selectAction,
} from "../src/policy";

const policy = parsePolicy(JSON.stringify({
  version: 1,
  default_provider: "codex",
  default_permission_profile: "workspace_write",
  max_steps: 2,
  rules: [{
    terms: ["analyze"],
    provider: "claude",
    fallback_provider: "codex",
    permission_profile: "read_only",
    max_steps: 1,
  }],
}));

describe("explicit provider preference", () => {
  it("honors a backend explicitly targeted inside an Auto-mode task", () => {
    expect(resolveProviderPreference("코덱스한테 말시켜봐", "auto")).toBe("codex");
    expect(resolveProviderPreference("클로드에게 이 검수를 맡겨", "auto")).toBe("claude");
    expect(resolveProviderPreference("Please ask Codex to implement it", "auto")).toBe("codex");
    expect(resolveProviderPreference("Use Claude Code for this review", "auto")).toBe("claude");
  });

  it("keeps an explicit UI selection authoritative", () => {
    expect(resolveProviderPreference("Claude should review this", "codex")).toBe("codex");
    expect(resolveProviderPreference("코덱스한테 시켜", "claude")).toBe("claude");
  });

  it("leaves ambiguous cross-backend prompts to RCC", () => {
    expect(resolveProviderPreference("Codex와 Claude를 비교해", "auto")).toBe("auto");
    expect(resolveProviderPreference("Codex에게 구현시키고 Claude에게 검수시켜", "auto")).toBe("auto");
  });

  it("does not mistake a larger identifier for a backend directive", () => {
    expect(resolveProviderPreference("reply OS1_CODEXISH_OK", "auto")).toBe("auto");
  });

  it("keeps RCC policy selection in auto mode", () => {
    expect(select(policy, "analyze the repository", "auto")).toEqual({
      provider: "claude",
      fallback_provider: "codex",
      permission_profile: "read_only",
      max_steps: 1,
      budget_protected: true,
    });
  });

  it("starts with the selected engine and preserves the governed permission", () => {
    expect(select(policy, "analyze the repository", "codex")).toEqual({
      provider: "codex",
      fallback_provider: "codex",
      permission_profile: "workspace_write",
      max_steps: 2,
      budget_protected: true,
    });
    expect(select(policy, "fix the repository", "claude")).toEqual({
      provider: "claude",
      fallback_provider: "claude",
      permission_profile: "workspace_write",
      max_steps: 2,
      budget_protected: true,
    });
  });

  it("spends scarce Codex capacity only at its configured weekly share", () => {
    const flexible = select(policy, "build the repository", "auto");
    expect(chooseCapacityAware(flexible, { codex: 25, claude: 100 }, { codex: 0, claude: 0 })).toBe("claude");
    expect(chooseCapacityAware(flexible, { codex: 25, claude: 100 }, { codex: 0, claude: 2 })).toBe("codex");
  });

  it("uses deep tiers for protected specialist rules", () => {
    const specialist = select(policy, "analyze the repository", "auto");
    expect(selectAction(specialist, "claude", "auto")).toBe("agent_run_deep");
  });

  it("uses efficient tiers when capacity moves a flexible task", () => {
    const flexible = select(policy, "build the repository", "auto");
    expect(selectAction(flexible, "claude", "auto")).toBe("agent_run_efficient");
    expect(selectAction(flexible, "codex", "auto")).toBe("agent_run");
  });

  it("does not match ASCII routing terms inside larger identifiers", () => {
    expect(select(policy, "reply exactly OS1_REANALYZE_OK", "auto").budget_protected).toBe(false);
  });

  it("keeps explicit provider overrides on the account default model", () => {
    const manual = select(policy, "analyze the repository", "codex");
    expect(selectAction(manual, "codex", "codex")).toBe("agent_run");
  });
});
