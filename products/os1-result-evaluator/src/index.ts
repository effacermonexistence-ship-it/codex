const SHA256 = /^[0-9a-f]{64}$/;
const ARTIFACT_REF = /^r2:\/\/os1-private-results\/([0-9a-f-]{36})\/([1-9][0-9]{0,5})\/([0-9a-f]{64})\.json$/i;

async function sha256Hex(bytes: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function equalHex(left: string, right: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}

function transientPatterns(serialized: string): string[] {
  const value = JSON.parse(serialized) as unknown;
  if (
    !Array.isArray(value) ||
    value.length > 64 ||
    value.some((item) => typeof item !== "string" || item.length < 3 || item.length > 128)
  ) {
    throw new Error("invalid evaluator policy");
  }
  return value;
}

function parseArtifact(value: unknown): {
  provider: "codex" | "claude";
  exit_code: number;
  output: string;
  stderr: string;
} {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new Error("invalid");
  const body = value as Record<string, unknown>;
  if (
    body.schema !== 1 ||
    !["codex", "claude"].includes(String(body.provider)) ||
    !Number.isSafeInteger(body.exit_code) ||
    typeof body.output !== "string" ||
    body.output.length > 800_000 ||
    typeof body.stderr !== "string" ||
    body.stderr.length > 200_000 ||
    !Number.isSafeInteger(body.duration_ms) ||
    typeof body.workspace_diff_hash !== "string" ||
    !SHA256.test(body.workspace_diff_hash)
  ) {
    throw new Error("invalid");
  }
  return {
    provider: body.provider as "codex" | "claude",
    exit_code: body.exit_code as number,
    output: body.output,
    stderr: body.stderr,
  };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      if (request.method !== "POST" || new URL(request.url).pathname !== "/evaluate") throw new Error("denied");
      const body = await request.json<unknown>();
      if (typeof body !== "object" || body === null || Array.isArray(body)) throw new Error("denied");
      const value = body as Record<string, unknown>;
      if (
        typeof value.artifact_ref !== "string" ||
        typeof value.expected_artifact_hash !== "string" ||
        !SHA256.test(value.expected_artifact_hash)
      ) {
        throw new Error("denied");
      }
      const match = value.artifact_ref.match(ARTIFACT_REF);
      if (!match || match[3] !== value.expected_artifact_hash) throw new Error("denied");
      const key = value.artifact_ref.slice("r2://os1-private-results/".length);
      const object = await env.RESULTS.get(key);
      if (!object || object.size < 2 || object.size > 1_048_576) throw new Error("denied");
      const bytes = await object.arrayBuffer();
      const verifiedHash = await sha256Hex(bytes);
      if (!(await equalHex(verifiedHash, value.expected_artifact_hash))) throw new Error("denied");
      const artifact = parseArtifact(
        JSON.parse(
          new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes),
        ),
      );
      const text = `${artifact.output}\n${artifact.stderr}`.toLocaleLowerCase("und");
      const transient = transientPatterns(env.TRANSIENT_FAILURE_PATTERNS_JSON).some((pattern) =>
        text.includes(pattern.toLocaleLowerCase("und")),
      );
      const outcome = artifact.exit_code === 0 && artifact.output.trim().length > 0
        ? "pass"
        : transient
          ? "retry"
          : "fail";
      return Response.json({ outcome, verified_artifact_hash: verifiedHash });
    } catch {
      return Response.json({ error: "denied" }, { status: 400 });
    }
  },
} satisfies ExportedHandler<Env>;
