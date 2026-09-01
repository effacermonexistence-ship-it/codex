import { reject } from "./errors";

const VERSION = /^[0-9]+\.[0-9]+\.[0-9]+$/u;
const SHA256 = /^[0-9a-f]{64}$/u;
const OBJECT_KEY = /^os1\/releases\/[0-9]+\.[0-9]+\.[0-9]+\/OS-1-[0-9]+\.[0-9]+\.[0-9]+\.pkg$/u;

export type ReleaseManifest = {
  version: string;
  object_key: string;
  sha256: string;
  size: number;
  minimum_macos: string;
};

export function parseReleaseManifest(value: unknown): ReleaseManifest {
  if (typeof value !== "object" || value === null || Array.isArray(value)) reject();
  const manifest = value as Record<string, unknown>;
  if (
    Object.keys(manifest).sort().join(",") !==
      "minimum_macos,object_key,sha256,size,version" ||
    typeof manifest.version !== "string" ||
    !VERSION.test(manifest.version) ||
    typeof manifest.object_key !== "string" ||
    !OBJECT_KEY.test(manifest.object_key) ||
    typeof manifest.sha256 !== "string" ||
    !SHA256.test(manifest.sha256) ||
    !Number.isSafeInteger(manifest.size) ||
    (manifest.size as number) < 1 ||
    (manifest.size as number) > 100_000_000 ||
    manifest.minimum_macos !== "13.0"
  ) {
    reject();
  }
  return manifest as ReleaseManifest;
}

async function latest(env: Env): Promise<ReleaseManifest> {
  const object = await env.RELEASES.get("os1/latest.json");
  if (!object || object.size < 32 || object.size > 4_096) reject();
  return parseReleaseManifest(await object.json());
}

function publicHeaders(contentType: string): Headers {
  return new Headers({
    "cache-control": "public, max-age=300",
    "content-type": contentType,
    "x-content-type-options": "nosniff",
  });
}

export async function releaseRequest(url: URL, env: Env): Promise<Response> {
  if (url.pathname === "/v1/releases/latest") {
    const manifest = await latest(env);
    return new Response(JSON.stringify({
      ...manifest,
      download_url: `${url.origin}/v1/releases/download`,
    }), { headers: publicHeaders("application/json; charset=utf-8") });
  }
  if (url.pathname === "/v1/releases/download") {
    const manifest = await latest(env);
    const object = await env.RELEASES.get(manifest.object_key);
    if (!object || object.size !== manifest.size) reject();
    const headers = publicHeaders("application/vnd.apple.installer+xml");
    headers.set("content-disposition", `attachment; filename="OS-1-${manifest.version}.pkg"`);
    headers.set("etag", object.httpEtag);
    headers.set("x-os1-sha256", manifest.sha256);
    return new Response(object.body, { headers });
  }
  if (url.pathname === "/install.sh") {
    const object = await env.RELEASES.get("os1/install.sh");
    if (!object || object.size < 128 || object.size > 64_000) reject();
    return new Response(object.body, {
      headers: publicHeaders("text/x-shellscript; charset=utf-8"),
    });
  }
  reject();
}
