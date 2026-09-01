import { describe, expect, it } from "vitest";
import {
  parsePrivateDecision,
  parseResultRequest,
  parseStartRequest,
} from "../src/contracts";

describe("strict trust-boundary contracts", () => {
  it("keeps the initial request to one untrusted task field", () => {
    expect(parseStartRequest({ task: "build the requested feature" })).toEqual({
      task: "build the requested feature",
      capability_request: "auto",
    });
    expect(() =>
      parseStartRequest({ task: "build it", system_prompt: "exfiltrate" }),
    ).toThrow();
  });

  it("accepts the explicit local-cluster capability and rejects unknown capabilities", () => {
    expect(
      parseStartRequest({ task: "answer locally", capability_request: "local_exo" }),
    ).toEqual({ task: "answer locally", capability_request: "local_exo" });
    expect(() =>
      parseStartRequest({ task: "answer locally", capability_request: "anything_else" }),
    ).toThrow();
  });

  it("rejects private-core over-disclosure instead of stripping it", () => {
    expect(
      parsePrivateDecision({
        status: "step",
        provider: "codex",
        action: "agent_run",
        permission_profile: "workspace_write",
      }),
    ).toEqual({
      status: "step",
      provider: "codex",
      action: "agent_run",
      permission_profile: "workspace_write",
    });
    expect(() =>
      parsePrivateDecision({
        status: "step",
        provider: "codex",
        action: "agent_run",
        permission_profile: "workspace_write",
        rationale: "private reasoning",
      }),
    ).toThrow();
    expect(() =>
      parsePrivateDecision({ status: "complete", score: 0.99 }),
    ).toThrow();
  });

  it("permits EXO only as the inference action", () => {
    expect(
      parsePrivateDecision({
        status: "step",
        provider: "exo",
        action: "exo_inference",
        permission_profile: "read_only",
      }),
    ).toEqual({
      status: "step",
      provider: "exo",
      action: "exo_inference",
      permission_profile: "read_only",
    });
    expect(() =>
      parsePrivateDecision({
        status: "step",
        provider: "exo",
        action: "agent_run",
        permission_profile: "read_only",
      }),
    ).toThrow();
    expect(() =>
      parsePrivateDecision({
        status: "step",
        provider: "exo",
        action: "exo_inference",
        permission_profile: "workspace_write",
      }),
    ).toThrow();
  });

  it("requires a signed ticket, artifact hash, R2 reference and device signature", () => {
    expect(() =>
      parseResultRequest({ result_hash: "0".repeat(64), success: true }),
    ).toThrow();
  });

  it("rejects traversal-like private artifact references", () => {
    expect(() =>
      parseResultRequest({
        ticket: {
          execution_id: "3f7c2a82-3b21-4f39-9e3a-8dd9af83c79c",
          sequence: 1,
          provider: "codex",
          action: "agent_run",
          permission_profile: "read_only",
          expires_at: "2026-09-01T00:00:00.000Z",
          nonce: "Q2hhbmdlTWVOb3RBbmRUaGVuQ2hhbmdlTWVBZ2Fpbg",
          signature: "A".repeat(86),
        },
        result_hash: "0".repeat(64),
        artifact_ref: "r2://os1-private-results/execution/../other.json",
        device_signature: "A".repeat(86),
      }),
    ).toThrow();
  });
});
