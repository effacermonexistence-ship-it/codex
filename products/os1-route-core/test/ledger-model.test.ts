import { describe, expect, it } from "vitest";
import { decideClaim, type ExecutionSnapshot } from "../src/ledger-model";

const execution: ExecutionSnapshot = {
  execution_id: "3f7c2a82-3b21-4f39-9e3a-8dd9af83c79c",
  subject_hash: "a".repeat(64),
  device_id: "device:test:01",
  sequence: 2,
  nonce: "nonce-2",
  expires_at: 10_000,
  phase: "active",
};

describe("atomic result claim decisions", () => {
  it("claims one matching result", () => {
    expect(
      decideClaim(execution, undefined, {
        subject_hash: execution.subject_hash,
        device_id: execution.device_id,
        sequence: 2,
        nonce: "nonce-2",
        result_hash: "b".repeat(64),
        now: 9_000,
      }),
    ).toEqual({ kind: "claimed" });
  });

  it("rejects nonce replay with changed content", () => {
    expect(
      decideClaim(
        execution,
        {
          sequence: 2,
          nonce: "nonce-2",
          result_hash: "b".repeat(64),
          response_json: null,
        },
        {
          subject_hash: execution.subject_hash,
          device_id: execution.device_id,
          sequence: 2,
          nonce: "nonce-2",
          result_hash: "c".repeat(64),
          now: 9_000,
        },
      ),
    ).toEqual({ kind: "rejected" });
  });

  it("rejects an identical concurrent submission while evaluation is pending", () => {
    expect(
      decideClaim(
        execution,
        {
          sequence: 2,
          nonce: "nonce-2",
          result_hash: "b".repeat(64),
          response_json: null,
        },
        {
          subject_hash: execution.subject_hash,
          device_id: execution.device_id,
          sequence: 2,
          nonce: "nonce-2",
          result_hash: "b".repeat(64),
          now: 9_000,
        },
      ),
    ).toEqual({ kind: "rejected" });
  });

  it("returns the identical stored response for an idempotent retry", () => {
    expect(
      decideClaim(
        execution,
        {
          sequence: 2,
          nonce: "nonce-2",
          result_hash: "b".repeat(64),
          response_json: '{"status":"complete"}',
        },
        {
          subject_hash: execution.subject_hash,
          device_id: execution.device_id,
          sequence: 2,
          nonce: "nonce-2",
          result_hash: "b".repeat(64),
          now: 12_000,
        },
      ),
    ).toEqual({ kind: "completed", response_json: '{"status":"complete"}' });
  });

  it("does not disclose a stored response to another authenticated device", () => {
    expect(
      decideClaim(
        execution,
        {
          sequence: 2,
          nonce: "nonce-2",
          result_hash: "b".repeat(64),
          response_json: '{"status":"complete"}',
        },
        {
          subject_hash: execution.subject_hash,
          device_id: "device:attacker:01",
          sequence: 2,
          nonce: "nonce-2",
          result_hash: "b".repeat(64),
          now: 9_000,
        },
      ),
    ).toEqual({ kind: "rejected" });
  });
});
