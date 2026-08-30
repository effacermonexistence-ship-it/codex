import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";

const GITHUB_OIDC_ISSUER = "https://token.actions.githubusercontent.com";
const GITHUB_JWKS = createRemoteJWKSet(
  new URL(`${GITHUB_OIDC_ISSUER}/.well-known/jwks`),
);
const WORKFLOW_PATH = ".github/workflows/r2-git-backup.yml";
const MAX_JSON_BYTES = 1_048_576;
const MAX_PART_BYTES = 32 * 1024 * 1024;

type GitHubClaims = JWTPayload & {
  repository: string;
  repository_owner: string;
  sha: string;
  ref: string;
  run_id: string;
  run_attempt: string;
  workflow_ref: string;
  event_name: "push" | "schedule" | "workflow_dispatch";
};

type CompleteRequest = {
  key: string;
  uploadId: string;
  parts: R2UploadedPart[];
  sha256: string;
  size: number;
};

type AbortRequest = {
  key: string;
  uploadId: string;
};

type BackupManifest = {
  version: 1;
  repository: string;
  sha: string;
  ref: string;
  runId: string;
  runAttempt: string;
  key: string;
  size: number;
  sha256: string;
  etag: string;
  uploadedAt: string;
};

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

function json(data: unknown, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  headers.set("cache-control", "no-store");
  headers.set("content-type", "application/json; charset=utf-8");
  headers.set("x-content-type-options", "nosniff");
  return new Response(JSON.stringify(data), { ...init, headers });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requiredString(
  value: unknown,
  field: string,
  pattern?: RegExp,
): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpError(400, `Invalid ${field}`);
  }
  if (pattern && !pattern.test(value)) {
    throw new HttpError(400, `Invalid ${field}`);
  }
  return value;
}

async function readJson(request: Request): Promise<unknown> {
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_JSON_BYTES) {
    throw new HttpError(413, "JSON request is too large");
  }
  try {
    return await request.json<unknown>();
  } catch {
    throw new HttpError(400, "Invalid JSON body");
  }
}

function assertClaims(
  payload: JWTPayload,
  env: Env,
): asserts payload is GitHubClaims {
  const repositoryOwner = requiredString(
    payload.repository_owner,
    "repository_owner",
    /^[A-Za-z0-9_.-]+$/,
  );
  const repository = requiredString(
    payload.repository,
    "repository",
    /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/,
  );
  const sha = requiredString(payload.sha, "sha", /^[0-9a-f]{40,64}$/i);
  const runId = requiredString(payload.run_id, "run_id", /^\d+$/);
  const runAttempt = requiredString(payload.run_attempt, "run_attempt", /^\d+$/);
  const workflowRef = requiredString(payload.workflow_ref, "workflow_ref");
  const eventName = requiredString(payload.event_name, "event_name");
  requiredString(payload.ref, "ref");

  if (repositoryOwner !== env.ALLOWED_OWNER) {
    throw new HttpError(403, "Repository owner is not allowed");
  }
  if (!repository.startsWith(`${repositoryOwner}/`)) {
    throw new HttpError(403, "Repository claim does not match its owner");
  }
  if (!workflowRef.startsWith(`${repository}/${WORKFLOW_PATH}@`)) {
    throw new HttpError(403, "Unapproved workflow");
  }
  if (
    eventName !== "push" &&
    eventName !== "schedule" &&
    eventName !== "workflow_dispatch"
  ) {
    throw new HttpError(403, "Unapproved workflow event");
  }

  void sha;
  void runId;
  void runAttempt;
}

async function authenticate(request: Request, env: Env): Promise<GitHubClaims> {
  const authorization = request.headers.get("authorization");
  const match = authorization?.match(/^Bearer ([^\s]+)$/);
  if (!match?.[1]) {
    throw new HttpError(401, "Missing bearer token");
  }

  try {
    const { payload } = await jwtVerify(match[1], GITHUB_JWKS, {
      issuer: GITHUB_OIDC_ISSUER,
      audience: env.OIDC_AUDIENCE,
      algorithms: ["RS256"],
    });
    assertClaims(payload, env);
    return payload;
  } catch (error) {
    if (error instanceof HttpError) {
      throw error;
    }
    throw new HttpError(401, "Invalid GitHub OIDC token");
  }
}

function objectKey(claims: GitHubClaims): string {
  return [
    "git-bundles",
    claims.repository,
    claims.sha,
    `${claims.run_id}-${claims.run_attempt}.bundle`,
  ].join("/");
}

function assertExpectedKey(value: unknown, claims: GitHubClaims): string {
  const key = requiredString(value, "key");
  if (key !== objectKey(claims)) {
    throw new HttpError(403, "Object key does not match this workflow run");
  }
  return key;
}

function validateParts(value: unknown): R2UploadedPart[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > 10_000) {
    throw new HttpError(400, "Invalid multipart parts");
  }

  const parts = value.map((part, index) => {
    if (!isRecord(part)) {
      throw new HttpError(400, "Invalid multipart part");
    }
    const partNumber = part.partNumber;
    const etag = part.etag;
    if (
      !Number.isInteger(partNumber) ||
      partNumber !== index + 1 ||
      typeof etag !== "string" ||
      etag.length < 2 ||
      etag.length > 256
    ) {
      throw new HttpError(400, "Multipart parts must be sequential");
    }
    return { partNumber, etag } satisfies R2UploadedPart;
  });

  return parts;
}

function parseCompleteRequest(
  value: unknown,
  claims: GitHubClaims,
): CompleteRequest {
  if (!isRecord(value)) {
    throw new HttpError(400, "Invalid completion request");
  }
  const key = assertExpectedKey(value.key, claims);
  const uploadId = requiredString(value.uploadId, "uploadId");
  const parts = validateParts(value.parts);
  const sha256 = requiredString(value.sha256, "sha256", /^[0-9a-f]{64}$/i);
  const size = value.size;
  if (typeof size !== "number" || !Number.isSafeInteger(size) || size <= 0) {
    throw new HttpError(400, "Invalid bundle size");
  }
  return { key, uploadId, parts, sha256: sha256.toLowerCase(), size };
}

function parseAbortRequest(value: unknown, claims: GitHubClaims): AbortRequest {
  if (!isRecord(value)) {
    throw new HttpError(400, "Invalid abort request");
  }
  return {
    key: assertExpectedKey(value.key, claims),
    uploadId: requiredString(value.uploadId, "uploadId"),
  };
}

async function startUpload(env: Env, claims: GitHubClaims): Promise<Response> {
  const key = objectKey(claims);
  const upload = await env.GIT_BACKUPS.createMultipartUpload(key, {
    customMetadata: {
      repository: claims.repository,
      sha: claims.sha,
      ref: claims.ref,
      runId: claims.run_id,
      runAttempt: claims.run_attempt,
    },
  });
  return json({ key, uploadId: upload.uploadId, partSize: MAX_PART_BYTES });
}

async function uploadPart(
  request: Request,
  env: Env,
  claims: GitHubClaims,
  url: URL,
): Promise<Response> {
  const key = assertExpectedKey(url.searchParams.get("key"), claims);
  const uploadId = requiredString(url.searchParams.get("uploadId"), "uploadId");
  const partNumber = Number(url.searchParams.get("partNumber"));
  const contentLength = Number(request.headers.get("content-length") ?? "0");

  if (!Number.isInteger(partNumber) || partNumber < 1 || partNumber > 10_000) {
    throw new HttpError(400, "Invalid partNumber");
  }
  if (!request.body) {
    throw new HttpError(400, "Missing part body");
  }
  if (
    !Number.isFinite(contentLength) ||
    contentLength <= 0 ||
    contentLength > MAX_PART_BYTES
  ) {
    throw new HttpError(413, "Invalid part size");
  }

  const upload = env.GIT_BACKUPS.resumeMultipartUpload(key, uploadId);
  const part = await upload.uploadPart(partNumber, request.body);
  return json(part);
}

async function completeUpload(
  request: Request,
  env: Env,
  claims: GitHubClaims,
): Promise<Response> {
  const body = parseCompleteRequest(await readJson(request), claims);
  const upload = env.GIT_BACKUPS.resumeMultipartUpload(body.key, body.uploadId);
  const object = await upload.complete(body.parts);

  if (object.size !== body.size) {
    await env.GIT_BACKUPS.delete(body.key);
    throw new HttpError(400, "Uploaded object size does not match the bundle");
  }

  const manifest: BackupManifest = {
    version: 1,
    repository: claims.repository,
    sha: claims.sha,
    ref: claims.ref,
    runId: claims.run_id,
    runAttempt: claims.run_attempt,
    key: body.key,
    size: object.size,
    sha256: body.sha256,
    etag: object.httpEtag,
    uploadedAt: new Date().toISOString(),
  };
  const manifestJson = JSON.stringify(manifest, null, 2);
  const latestKey = `git-bundles/${claims.repository}/latest.json`;
  const runKey = `git-bundles/${claims.repository}/runs/${claims.run_id}-${claims.run_attempt}.json`;

  await Promise.all([
    env.GIT_BACKUPS.put(latestKey, manifestJson, {
      httpMetadata: { contentType: "application/json" },
    }),
    env.GIT_BACKUPS.put(runKey, manifestJson, {
      httpMetadata: { contentType: "application/json" },
    }),
  ]);

  return json(manifest, { status: 201, headers: { etag: object.httpEtag } });
}

async function abortUpload(
  request: Request,
  env: Env,
  claims: GitHubClaims,
): Promise<Response> {
  const body = parseAbortRequest(await readJson(request), claims);
  const upload = env.GIT_BACKUPS.resumeMultipartUpload(body.key, body.uploadId);
  await upload.abort();
  return new Response(null, { status: 204 });
}

async function handle(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/health") {
    return json({ ok: true, service: "omar-git-r2-backup", version: 1 });
  }

  const claims = await authenticate(request, env);
  if (request.method === "POST" && url.pathname === "/v1/uploads") {
    return startUpload(env, claims);
  }
  if (request.method === "PUT" && url.pathname === "/v1/uploads/part") {
    return uploadPart(request, env, claims, url);
  }
  if (request.method === "POST" && url.pathname === "/v1/uploads/complete") {
    return completeUpload(request, env, claims);
  }
  if (request.method === "POST" && url.pathname === "/v1/uploads/abort") {
    return abortUpload(request, env, claims);
  }
  throw new HttpError(404, "Not found");
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const response = await handle(request, env);
      console.log(
        JSON.stringify({
          message: "request completed",
          method: request.method,
          path: new URL(request.url).pathname,
          status: response.status,
        }),
      );
      return response;
    } catch (error) {
      const status = error instanceof HttpError ? error.status : 500;
      const message = error instanceof HttpError ? error.message : "Internal server error";
      console.error(
        JSON.stringify({
          message: "request failed",
          method: request.method,
          path: new URL(request.url).pathname,
          status,
          error: error instanceof Error ? error.message : String(error),
        }),
      );
      return json({ error: message }, { status });
    }
  },
} satisfies ExportedHandler<Env>;
