import { DurableObject } from "cloudflare:workers";

type RecordValue = {
  subject: string;
  device_id: string;
  p256_public_jwk: JsonWebKey;
};

const DEVICE_ID = /^[A-Za-z0-9._:-]{8,128}$/;
const BASE64URL = /^[A-Za-z0-9_-]{40,64}$/;

function parseIdentity(value: unknown): Pick<RecordValue, "subject" | "device_id"> | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, unknown>;
  if (
    typeof record.subject !== "string" ||
    record.subject.length < 1 ||
    record.subject.length > 256 ||
    typeof record.device_id !== "string" ||
    !DEVICE_ID.test(record.device_id)
  ) {
    return null;
  }
  return { subject: record.subject, device_id: record.device_id };
}

function parseRecord(value: unknown): RecordValue | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  const record = value as Record<string, unknown>;
  const identity = parseIdentity(value);
  if (
    !identity ||
    Object.keys(record).sort().join(",") !==
      "device_id,p256_public_jwk,subject" ||
    typeof record.subject !== "string" ||
    record.subject.length < 1 ||
    record.subject.length > 256 ||
    typeof record.device_id !== "string" ||
    !DEVICE_ID.test(record.device_id) ||
    typeof record.p256_public_jwk !== "object" ||
    record.p256_public_jwk === null ||
    Array.isArray(record.p256_public_jwk)
  ) {
    return null;
  }
  const jwk = record.p256_public_jwk as Record<string, unknown>;
  if (
    Object.keys(jwk).sort().join(",") !== "crv,kty,x,y" ||
    jwk.kty !== "EC" ||
    jwk.crv !== "P-256" ||
    typeof jwk.x !== "string" ||
    !BASE64URL.test(jwk.x) ||
    typeof jwk.y !== "string" ||
    !BASE64URL.test(jwk.y)
  ) {
    return null;
  }
  return {
    subject: identity.subject,
    device_id: identity.device_id,
    p256_public_jwk: { kty: "EC", crv: "P-256", x: jwk.x, y: jwk.y },
  };
}

export class DeviceRecord extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS device (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          subject TEXT NOT NULL,
          device_id TEXT NOT NULL,
          jwk_json TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      `);
    });
  }

  register(value: RecordValue): "registered" | "conflict" {
    return this.ctx.storage.transactionSync(() => {
      const existing = this.ctx.storage.sql
        .exec<{ subject: string; device_id: string; jwk_json: string }>(
          "SELECT subject,device_id,jwk_json FROM device WHERE singleton=1",
        )
        .toArray()[0];
      const jwkJson = JSON.stringify(value.p256_public_jwk);
      if (existing) {
        return existing.subject === value.subject &&
          existing.device_id === value.device_id &&
          existing.jwk_json === jwkJson
          ? "registered"
          : "conflict";
      }
      this.ctx.storage.sql.exec(
        "INSERT INTO device(singleton,subject,device_id,jwk_json,created_at) VALUES(1,?,?,?,?)",
        value.subject,
        value.device_id,
        jwkJson,
        Date.now(),
      );
      return "registered";
    });
  }

  lookup(): RecordValue | null {
    const row = this.ctx.storage.sql
      .exec<{ subject: string; device_id: string; jwk_json: string }>(
        "SELECT subject,device_id,jwk_json FROM device WHERE singleton=1",
      )
      .toArray()[0];
    if (!row) return null;
    return {
      subject: row.subject,
      device_id: row.device_id,
      p256_public_jwk: JSON.parse(row.jwk_json) as JsonWebKey,
    };
  }
}

async function subjectKey(subject: string, deviceId: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${subject}\n${deviceId}`),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      if (request.method !== "POST") return Response.json({ error: "denied" }, { status: 400 });
      const body = await request.json<unknown>();
      if (url.pathname === "/register") {
        const value = parseRecord(body);
        if (!value) return Response.json({ error: "denied" }, { status: 400 });
        const stub = env.DEVICES.getByName(await subjectKey(value.subject, value.device_id));
        const status = await stub.register(value);
        return status === "registered"
          ? Response.json({ status })
          : Response.json({ error: "denied" }, { status: 409 });
      }
      if (url.pathname === "/lookup") {
        const value = parseIdentity(body);
        if (
          !value ||
          typeof body !== "object" ||
          body === null ||
          Array.isArray(body) ||
          Object.keys(body).sort().join(",") !== "device_id,subject"
        ) {
          return Response.json({ error: "denied" }, { status: 400 });
        }
        const stub = env.DEVICES.getByName(await subjectKey(value.subject, value.device_id));
        const result = await stub.lookup();
        if (!result || result.subject !== value.subject || result.device_id !== value.device_id) {
          return Response.json({ error: "denied" }, { status: 404 });
        }
        return Response.json(result);
      }
      return Response.json({ error: "denied" }, { status: 400 });
    } catch {
      return Response.json({ error: "denied" }, { status: 400 });
    }
  },
} satisfies ExportedHandler<Env>;
