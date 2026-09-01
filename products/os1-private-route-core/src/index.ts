import { DurableObject } from "cloudflare:workers";

type Provider = "codex" | "claude" | "exo";
type Action = "agent_run" | "exo_inference";
type PermissionProfile = "read_only" | "workspace_write" | "full_access";
type Step = {
  provider: Provider;
  fallback_provider: Provider;
  permission_profile: PermissionProfile;
  max_steps: number;
};
type Rule = Step & { terms: string[] };
type Policy = {
  version: 1;
  default_provider: Provider;
  default_permission_profile: PermissionProfile;
  max_steps: number;
  local_exo_enabled: boolean;
  rules: Rule[];
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const providers = new Set<Provider>(["codex", "claude", "exo"]);
const permissions = new Set<PermissionProfile>([
  "read_only",
  "workspace_write",
  "full_access",
]);

function isProvider(value: unknown): value is Provider {
  return typeof value === "string" && providers.has(value as Provider);
}

function isPermission(value: unknown): value is PermissionProfile {
  return typeof value === "string" && permissions.has(value as PermissionProfile);
}

function actionFor(provider: Provider): Action {
  return provider === "exo" ? "exo_inference" : "agent_run";
}

function validStep(provider: Provider, permissionProfile: PermissionProfile): boolean {
  // EXO is an inference-only provider. It must never receive a ticket that
  // implies workspace mutation or unrestricted local execution.
  return provider !== "exo" || permissionProfile === "read_only";
}

function parsePolicy(serialized: string): Policy {
  const value = JSON.parse(serialized) as Record<string, unknown>;
  if (
    value.version !== 1 ||
    !isProvider(value.default_provider) ||
    !isPermission(value.default_permission_profile) ||
    !validStep(value.default_provider, value.default_permission_profile) ||
    !Number.isSafeInteger(value.max_steps) ||
    (value.max_steps as number) < 1 ||
    (value.max_steps as number) > 4 ||
    !Array.isArray(value.rules) ||
    value.rules.length > 64 ||
    (value.local_exo_enabled !== undefined && typeof value.local_exo_enabled !== "boolean")
  ) {
    throw new Error("invalid policy");
  }
  const rules: Rule[] = value.rules.map((candidate) => {
    if (typeof candidate !== "object" || candidate === null || Array.isArray(candidate)) {
      throw new Error("invalid policy");
    }
    const rule = candidate as Record<string, unknown>;
    if (
      !isProvider(rule.provider) ||
      !isProvider(rule.fallback_provider) ||
      !isPermission(rule.permission_profile) ||
      !validStep(rule.provider, rule.permission_profile) ||
      !validStep(rule.fallback_provider, rule.permission_profile) ||
      !Number.isSafeInteger(rule.max_steps) ||
      (rule.max_steps as number) < 1 ||
      (rule.max_steps as number) > 4 ||
      !Array.isArray(rule.terms) ||
      rule.terms.length === 0 ||
      rule.terms.length > 64 ||
      rule.terms.some((term) => typeof term !== "string" || term.length < 2 || term.length > 128)
    ) {
      throw new Error("invalid policy");
    }
    return {
      provider: rule.provider,
      fallback_provider: rule.fallback_provider,
      permission_profile: rule.permission_profile,
      max_steps: rule.max_steps as number,
      terms: rule.terms as string[],
    };
  });
  return {
    version: 1,
    default_provider: value.default_provider,
    default_permission_profile: value.default_permission_profile,
    max_steps: value.max_steps as number,
    local_exo_enabled: value.local_exo_enabled === true,
    rules,
  };
}

function select(policy: Policy, task: string, capabilityRequest: "auto" | "local_exo"): Step {
  if (capabilityRequest === "local_exo" && policy.local_exo_enabled) {
    return {
      provider: "exo",
      fallback_provider: "codex",
      permission_profile: "read_only",
      max_steps: 1,
    };
  }
  const folded = task.toLocaleLowerCase("und");
  const rule = policy.rules.find((candidate) =>
    candidate.terms.some((term) => folded.includes(term.toLocaleLowerCase("und"))),
  );
  return rule ?? {
    provider: policy.default_provider,
    fallback_provider: policy.default_provider === "codex" ? "claude" : "codex",
    permission_profile: policy.default_permission_profile,
    max_steps: policy.max_steps,
  };
}

export class RouteState extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS route (
          singleton INTEGER PRIMARY KEY CHECK(singleton=1),
          provider TEXT NOT NULL,
          fallback_provider TEXT NOT NULL,
          permission_profile TEXT NOT NULL,
          max_steps INTEGER NOT NULL,
          sequence INTEGER NOT NULL,
          complete INTEGER NOT NULL DEFAULT 0
        )
      `);
    });
  }

  begin(step: Step): "created" | "exists" {
    return this.ctx.storage.transactionSync(() => {
      const existing = this.ctx.storage.sql
        .exec<{ present: number }>("SELECT 1 AS present FROM route WHERE singleton=1")
        .toArray()[0];
      if (existing) return "exists";
      this.ctx.storage.sql.exec(
        "INSERT INTO route(singleton,provider,fallback_provider,permission_profile,max_steps,sequence,complete) VALUES(1,?,?,?,?,1,0)",
        step.provider,
        step.fallback_provider,
        step.permission_profile,
        step.max_steps,
      );
      return "created";
    });
  }

  advance(sequence: number, outcome: "pass" | "fail" | "retry"):
    | { status: "complete" }
    | { status: "step"; provider: Provider; permission_profile: PermissionProfile } {
    return this.ctx.storage.transactionSync(() => {
      const row = this.ctx.storage.sql
        .exec<{
          provider: Provider;
          fallback_provider: Provider;
          permission_profile: PermissionProfile;
          max_steps: number;
          sequence: number;
          complete: number;
        }>("SELECT provider,fallback_provider,permission_profile,max_steps,sequence,complete FROM route WHERE singleton=1")
        .toArray()[0];
      if (!row || row.complete === 1 || row.sequence !== sequence) {
        throw new Error("invalid route state");
      }
      if (outcome === "pass" || sequence >= row.max_steps) {
        this.ctx.storage.sql.exec("UPDATE route SET complete=1 WHERE singleton=1");
        return { status: "complete" };
      }
      const provider = row.fallback_provider;
      this.ctx.storage.sql.exec(
        "UPDATE route SET provider=?,fallback_provider=?,sequence=? WHERE singleton=1",
        provider,
        row.provider,
        sequence + 1,
      );
      return { status: "step", provider, permission_profile: row.permission_profile };
    });
  }
}

function stepResponse(step: Pick<Step, "provider" | "permission_profile">): Response {
  return Response.json({
    status: "step",
    provider: step.provider,
    action: actionFor(step.provider),
    permission_profile: step.permission_profile,
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      if (request.method !== "POST" || new URL(request.url).pathname !== "/decide") {
        throw new Error("denied");
      }
      const body = await request.json<unknown>();
      if (typeof body !== "object" || body === null || Array.isArray(body)) throw new Error("denied");
      const value = body as Record<string, unknown>;
      if (typeof value.execution_id !== "string" || !UUID.test(value.execution_id)) throw new Error("denied");
      const state = env.ROUTES.getByName(value.execution_id);

      if (typeof value.task === "object" && value.task !== null && !Array.isArray(value.task)) {
        const task = value.task as Record<string, unknown>;
        if (
          task.trust !== "untrusted_user_data" ||
          typeof task.content !== "string" ||
          task.content.length > 48_000 ||
          !["auto", "local_exo"].includes(String(value.capability_request ?? "auto"))
        ) {
          throw new Error("denied");
        }
        const selected = select(
          parsePolicy(env.PRIVATE_ROUTE_POLICY_JSON),
          task.content,
          (value.capability_request ?? "auto") as "auto" | "local_exo",
        );
        if ((await state.begin(selected)) !== "created") throw new Error("denied");
        return stepResponse(selected);
      }
      if (typeof value.previous === "object" && value.previous !== null && !Array.isArray(value.previous)) {
        const previous = value.previous as Record<string, unknown>;
        if (
          !Number.isSafeInteger(previous.sequence) ||
          !["pass", "fail", "retry"].includes(String(previous.outcome))
        ) {
          throw new Error("denied");
        }
        const decision = await state.advance(
          previous.sequence as number,
          previous.outcome as "pass" | "fail" | "retry",
        );
        return decision.status === "complete" ? Response.json(decision) : stepResponse(decision);
      }
      throw new Error("denied");
    } catch {
      return Response.json({ error: "denied" }, { status: 400 });
    }
  },
} satisfies ExportedHandler<Env>;
