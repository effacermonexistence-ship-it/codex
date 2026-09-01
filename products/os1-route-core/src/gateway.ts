import {
  parseAuthIdentity,
  parseDeviceRecord,
  parseEvaluatedResult,
  parsePrivateDecision,
  parsePublicResponse,
  parseResultRequest,
  parseStartRequest,
  type AuthIdentity,
  type PrivateDecision,
  type PublicResponse,
  type Ticket,
  type TicketUnsigned,
} from "./contracts";
import {
  randomNonce,
  sha256Hex,
  signTicket,
  timingSafeHexEqual,
  verifyDeviceResult,
  verifyTicket,
} from "./crypto";
import { assertTicketDeliveryHygiene, publicJson } from "./egress";
import { reject } from "./errors";
import { bindingJson, readBoundedJson } from "./io";

function positiveInteger(value: string): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) reject();
  return parsed;
}

async function authenticate(request: Request, env: Env): Promise<AuthIdentity> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ") || authorization.length > 8_192) {
    reject();
  }
  const value = await bindingJson(
    env.AUTH_SERVICE,
    "/verify",
    {},
    positiveInteger(env.SERVICE_RESPONSE_BYTES),
    authorization,
  );
  return parseAuthIdentity(value);
}

async function privateDecision(
  env: Env,
  body: unknown,
): Promise<PrivateDecision> {
  return parsePrivateDecision(
    await bindingJson(
      env.PRIVATE_ROUTE_CORE,
      "/decide",
      body,
      positiveInteger(env.SERVICE_RESPONSE_BYTES),
    ),
  );
}

function unsignedTicket(
  executionId: string,
  sequence: number,
  decision: Extract<PrivateDecision, { status: "step" }>,
  ttlSeconds: number,
): TicketUnsigned {
  return {
    execution_id: executionId,
    sequence,
    provider: decision.provider,
    action: decision.action,
    permission_profile: decision.permission_profile,
    expires_at: new Date(Date.now() + ttlSeconds * 1_000).toISOString(),
    nonce: randomNonce(),
  };
}

async function issueTicket(
  env: Env,
  executionId: string,
  sequence: number,
  decision: Extract<PrivateDecision, { status: "step" }>,
): Promise<Ticket> {
  const ticket = await signTicket(
    unsignedTicket(
      executionId,
      sequence,
      decision,
      positiveInteger(env.TICKET_TTL_SECONDS),
    ),
    env.TICKET_SIGNING_KEY_PKCS8,
  );
  assertTicketDeliveryHygiene(ticket, env.DELIVERY_DENYLIST_JSON);
  return ticket;
}

export async function startExecution(request: Request, env: Env): Promise<Response> {
  const identity = await authenticate(request, env);
  const { task } = parseStartRequest(
    await readBoundedJson(request, positiveInteger(env.MAX_REQUEST_BYTES)),
  );
  const executionId = crypto.randomUUID();
  const decision = await privateDecision(env, {
    version: 1,
    execution_id: executionId,
    principal: { subject: identity.subject, device_id: identity.device_id },
    task: { trust: "untrusted_user_data", content: task },
  });
  if (decision.status === "complete") return publicJson({ status: "complete" });

  const ticket = await issueTicket(env, executionId, 1, decision);
  const state = env.EXECUTIONS.getByName(executionId);
  const created = await state.begin({
    execution_id: executionId,
    subject_hash: await sha256Hex(identity.subject),
    device_id: identity.device_id,
    sequence: ticket.sequence,
    nonce: ticket.nonce,
    expires_at: Date.parse(ticket.expires_at),
    phase: "active",
  });
  if (created !== "created") reject();
  return publicJson(ticket);
}

async function verifiedDeviceKey(
  env: Env,
  identity: AuthIdentity,
): Promise<JsonWebKey> {
  const record = parseDeviceRecord(
    await bindingJson(
      env.DEVICE_REGISTRY,
      "/lookup",
      { subject: identity.subject, device_id: identity.device_id },
      positiveInteger(env.SERVICE_RESPONSE_BYTES),
    ),
  );
  if (
    record.subject !== identity.subject ||
    record.device_id !== identity.device_id
  ) {
    reject();
  }
  return record.p256_public_jwk;
}

export async function submitResult(request: Request, env: Env): Promise<Response> {
  const identity = await authenticate(request, env);
  const result = parseResultRequest(
    await readBoundedJson(request, positiveInteger(env.MAX_REQUEST_BYTES)),
  );
  if (
    Date.parse(result.ticket.expires_at) < Date.now() ||
    !(await verifyTicket(result.ticket, env.TICKET_VERIFYING_KEY_SPKI))
  ) {
    reject();
  }
  const deviceKey = await verifiedDeviceKey(env, identity);
  if (!(await verifyDeviceResult(result, deviceKey))) reject();

  const state = env.EXECUTIONS.getByName(result.ticket.execution_id);
  const claim = await state.claim({
    subject_hash: await sha256Hex(identity.subject),
    device_id: identity.device_id,
    sequence: result.ticket.sequence,
    nonce: result.ticket.nonce,
    result_hash: result.result_hash,
    now: Date.now(),
  });
  if (claim.kind === "rejected") reject();
  if (claim.kind === "completed") {
    return publicJson(parsePublicResponse(JSON.parse(claim.response_json)));
  }

  const evaluated = parseEvaluatedResult(
    await bindingJson(
      env.RESULT_EVALUATOR,
      "/evaluate",
      {
        execution_id: result.ticket.execution_id,
        sequence: result.ticket.sequence,
        artifact_ref: result.artifact_ref,
        expected_artifact_hash: result.result_hash,
      },
      positiveInteger(env.SERVICE_RESPONSE_BYTES),
    ),
  );
  if (!timingSafeHexEqual(evaluated.verified_artifact_hash, result.result_hash)) {
    reject();
  }

  const decision = await privateDecision(env, {
    version: 1,
    execution_id: result.ticket.execution_id,
    previous: {
      sequence: result.ticket.sequence,
      outcome: evaluated.outcome,
      verified_artifact_hash: evaluated.verified_artifact_hash,
    },
  });
  let response: PublicResponse;
  let next: { sequence: number; nonce: string; expires_at: number } | null;
  if (decision.status === "complete") {
    response = { status: "complete" };
    next = null;
  } else {
    const ticket = await issueTicket(
      env,
      result.ticket.execution_id,
      result.ticket.sequence + 1,
      decision,
    );
    response = ticket;
    next = {
      sequence: ticket.sequence,
      nonce: ticket.nonce,
      expires_at: Date.parse(ticket.expires_at),
    };
  }

  const responseJson = JSON.stringify(response);
  const finalized = await state.finalize({
    sequence: result.ticket.sequence,
    result_hash: result.result_hash,
    response_json: responseJson,
    next,
  });
  if (finalized.kind === "rejected") reject();
  return publicJson(parsePublicResponse(JSON.parse(finalized.response_json)));
}
