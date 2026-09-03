import { describe, expect, it } from "vitest";
import type { ResultRequest, TicketUnsigned } from "../src/contracts";
import {
  canonicalResult,
  signTicket,
  verifyDeviceResult,
  verifyTicket,
} from "../src/crypto";

function pem(label: string, bytes: ArrayBuffer): string {
  const binary = String.fromCharCode(...new Uint8Array(bytes));
  const base64 = btoa(binary).match(/.{1,64}/gu)?.join("\n") ?? "";
  return `-----BEGIN ${label}-----\n${base64}\n-----END ${label}-----`;
}

describe("asymmetric ticket signatures", () => {
  it("accepts an intact ticket and rejects a changed routing field", async () => {
    const pair = (await crypto.subtle.generateKey(
      { name: "Ed25519" },
      true,
      ["sign", "verify"],
    )) as CryptoKeyPair;
    const privatePem = pem(
      "PRIVATE KEY",
      await crypto.subtle.exportKey("pkcs8", pair.privateKey),
    );
    const publicPem = pem(
      "PUBLIC KEY",
      await crypto.subtle.exportKey("spki", pair.publicKey),
    );
    const unsigned: TicketUnsigned = {
      execution_id: "3f7c2a82-3b21-4f39-9e3a-8dd9af83c79c",
      sequence: 1,
      provider: "codex",
      action: "agent_run",
      permission_profile: "workspace_write",
      expires_at: "2026-09-01T00:00:00.000Z",
      nonce: "Q2hhbmdlTWVOb3RBbmRUaGVuQ2hhbmdlTWVBZ2Fpbg",
    };
    const ticket = await signTicket(unsigned, privatePem);
    await expect(verifyTicket(ticket, publicPem)).resolves.toBe(true);
    await expect(
      verifyTicket({ ...ticket, permission_profile: "read_only" }, publicPem),
    ).resolves.toBe(false);
  });

  it("binds a device signature to the ticket, result hash, and artifact", async () => {
    const pair = (await crypto.subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign", "verify"],
    )) as CryptoKeyPair;
    const result: ResultRequest = {
      ticket: {
        execution_id: "3f7c2a82-3b21-4f39-9e3a-8dd9af83c79c",
        sequence: 2,
        provider: "codex",
        action: "agent_run",
        permission_profile: "workspace_write",
        expires_at: "2026-09-01T00:00:00.000Z",
        nonce: "Q2hhbmdlTWVOb3RBbmRUaGVuQ2hhbmdlTWVBZ2Fpbg",
        signature: "A".repeat(86),
      },
      result_hash: "b".repeat(64),
      artifact_ref: "r2://os1-private-results/execution/result.json",
      device_signature: "",
    };
    const signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      pair.privateKey,
      canonicalResult(result),
    );
    result.device_signature = Buffer.from(signature).toString("base64url");
    const publicJwk = await crypto.subtle.exportKey("jwk", pair.publicKey);

    await expect(verifyDeviceResult(result, publicJwk)).resolves.toBe(true);
    await expect(
      verifyDeviceResult(
        { ...result, result_hash: "c".repeat(64) },
        publicJwk,
      ),
    ).resolves.toBe(false);
  });
});
