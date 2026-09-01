const DEVICE_ID = /^[A-Za-z0-9._:-]{8,128}$/;

function denied(): Response {
  return Response.json({ error: "denied" }, { status: 401 });
}

function parseDeviceId(value: unknown): string | null {
  return typeof value === "string" && DEVICE_ID.test(value) ? value : null;
}

async function readDeviceId(request: Request): Promise<string | null> {
  const length = Number(request.headers.get("content-length") ?? "0");
  if (!Number.isFinite(length) || length > 512) return null;
  let value: unknown;
  try {
    value = await request.json<unknown>();
  } catch {
    return null;
  }
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value) ||
    Object.keys(value).length !== 1
  ) {
    return null;
  }
  return parseDeviceId((value as Record<string, unknown>).device_id);
}

async function verify(request: Request): Promise<Response> {
  const authorization = request.headers.get("authorization");
  const token = authorization?.match(/^Bearer ([^\s]{20,8192})$/u)?.[1];
  const deviceId = await readDeviceId(request);
  if (!token || !deviceId) return denied();

  const response = await fetch("https://api.github.com/user", {
    headers: {
      accept: "application/vnd.github+json",
      authorization: `Bearer ${token}`,
      "user-agent": "OS-1-route-gateway",
      "x-github-api-version": "2022-11-28",
    },
    signal: AbortSignal.timeout(5_000),
  });
  if (!response.ok) return denied();
  const body = await response.json<unknown>();
  if (
    typeof body !== "object" ||
    body === null ||
    Array.isArray(body) ||
    !Number.isSafeInteger((body as Record<string, unknown>).id)
  ) {
    return denied();
  }
  const id = (body as Record<string, unknown>).id as number;
  return Response.json({ subject: `github:${id}`, device_id: deviceId });
}

export default {
  async fetch(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url);
      if (request.method !== "POST" || url.pathname !== "/verify") {
        return denied();
      }
      return await verify(request);
    } catch {
      return denied();
    }
  },
} satisfies ExportedHandler<Env>;
