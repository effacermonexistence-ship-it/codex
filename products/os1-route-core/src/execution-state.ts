import { DurableObject } from "cloudflare:workers";
import type { ClaimCommand, ExecutionSnapshot, ResultSnapshot } from "./ledger-model";
import { decideClaim, type ClaimDecision } from "./ledger-model";

export type BeginCommand = ExecutionSnapshot;

export type FinalizeCommand = {
  sequence: number;
  result_hash: string;
  response_json: string;
  next:
    | null
    | { sequence: number; nonce: string; expires_at: number };
};

export type FinalizeDecision =
  | { kind: "stored"; response_json: string }
  | { kind: "completed"; response_json: string }
  | { kind: "rejected" };

type ExecutionRow = ExecutionSnapshot;
type ResultRow = ResultSnapshot;

export class ExecutionState extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS execution (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          execution_id TEXT NOT NULL UNIQUE,
          subject_hash TEXT NOT NULL,
          device_id TEXT NOT NULL,
          sequence INTEGER NOT NULL,
          nonce TEXT NOT NULL,
          expires_at INTEGER NOT NULL,
          phase TEXT NOT NULL CHECK (phase IN ('active', 'complete'))
        );
        CREATE TABLE IF NOT EXISTS results (
          sequence INTEGER PRIMARY KEY,
          nonce TEXT NOT NULL,
          result_hash TEXT NOT NULL,
          response_json TEXT
        );
      `);
    });
  }

  async begin(command: BeginCommand): Promise<"created" | "exists"> {
    return this.ctx.storage.transactionSync(() => {
      const existing = this.ctx.storage.sql
        .exec<{ execution_id: string }>(
          "SELECT execution_id FROM execution WHERE singleton = 1",
        )
        .toArray()[0];
      if (existing) return "exists";
      this.ctx.storage.sql.exec(
        `INSERT INTO execution
          (singleton, execution_id, subject_hash, device_id, sequence, nonce, expires_at, phase)
         VALUES (1, ?, ?, ?, ?, ?, ?, ?)`,
        command.execution_id,
        command.subject_hash,
        command.device_id,
        command.sequence,
        command.nonce,
        command.expires_at,
        command.phase,
      );
      return "created";
    });
  }

  async claim(command: ClaimCommand): Promise<ClaimDecision> {
    return this.ctx.storage.transactionSync(() => {
      const execution = this.ctx.storage.sql
        .exec<ExecutionRow>(
          `SELECT execution_id, subject_hash, device_id, sequence, nonce, expires_at, phase
           FROM execution WHERE singleton = 1`,
        )
        .toArray()[0];
      const previous = this.ctx.storage.sql
        .exec<ResultRow>(
          `SELECT sequence, nonce, result_hash, response_json
           FROM results WHERE sequence = ?`,
          command.sequence,
        )
        .toArray()[0];
      const decision = decideClaim(execution, previous, command);
      if (decision.kind === "claimed") {
        this.ctx.storage.sql.exec(
          `INSERT INTO results (sequence, nonce, result_hash, response_json)
           VALUES (?, ?, ?, NULL)`,
          command.sequence,
          command.nonce,
          command.result_hash,
        );
      }
      return decision;
    });
  }

  async finalize(command: FinalizeCommand): Promise<FinalizeDecision> {
    return this.ctx.storage.transactionSync(() => {
      const result = this.ctx.storage.sql
        .exec<ResultRow>(
          `SELECT sequence, nonce, result_hash, response_json
           FROM results WHERE sequence = ?`,
          command.sequence,
        )
        .toArray()[0];
      if (!result || result.result_hash !== command.result_hash) {
        return { kind: "rejected" };
      }
      if (result.response_json !== null) {
        return { kind: "completed", response_json: result.response_json };
      }
      this.ctx.storage.sql.exec(
        "UPDATE results SET response_json = ? WHERE sequence = ?",
        command.response_json,
        command.sequence,
      );
      if (command.next === null) {
        this.ctx.storage.sql.exec(
          "UPDATE execution SET phase = 'complete' WHERE singleton = 1",
        );
      } else {
        this.ctx.storage.sql.exec(
          `UPDATE execution
           SET sequence = ?, nonce = ?, expires_at = ?, phase = 'active'
           WHERE singleton = 1 AND sequence = ?`,
          command.next.sequence,
          command.next.nonce,
          command.next.expires_at,
          command.sequence,
        );
      }
      return { kind: "stored", response_json: command.response_json };
    });
  }
}
