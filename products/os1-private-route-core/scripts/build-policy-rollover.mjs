#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

function fail(message) {
  throw new Error(message);
}

const [configPath, outputPath, policyVersion, ...previousSpecs] = process.argv.slice(2);
if (!configPath || !outputPath || !policyVersion) {
  fail("usage: build-policy-rollover.mjs CONFIG OUTPUT POLICY_VERSION [VERSION:SHA256 ...]");
}

const config = JSON.parse(await readFile(configPath, "utf8"));
if (!config?.executor_contract || !config.execution_profiles ||
  !Number.isSafeInteger(config.maximum_steps) || config.maximum_steps < 1 || config.maximum_steps > 4) {
  fail("runtime config is missing execution profiles or executor contract");
}
const privateCore = process.env.OS1_PRIVATE_CORE_DIR;
if (!privateCore) fail("OS1_PRIVATE_CORE_DIR must point to the source-locked private core");
const adapterPath = join(privateCore, "os1_local_core.py");
const adapterSource = await readFile(adapterPath, "utf8");
const adapterVersion = adapterSource.match(/^ADAPTER_VERSION\s*=\s*"([A-Za-z0-9._-]{8,96})"/m)?.[1];
if (!adapterVersion) fail("private RCC adapter version is unavailable");
const python = process.env.PYTHON || "/usr/bin/python3";
const selfTest = spawnSync(python, [adapterPath, "self-test"], { encoding: "utf8", maxBuffer: 1_048_576 });
if (selfTest.status !== 0 || JSON.parse(selfTest.stdout || "null")?.status !== "ok") {
  fail("private RCC self-test failed");
}
const probe = spawnSync(python, [adapterPath, "route", "-"], {
  encoding: "utf8",
  input: JSON.stringify({ prompt: "1 plus 1", provider_preference: "auto", codex_capacity: 30,
    claude_capacity: 100, attempt: 1, state_dir: join(tmpdir(), "os1-policy-rollover-probe") }),
  maxBuffer: 1_048_576,
});
const identity = probe.status === 0 ? JSON.parse(probe.stdout || "null") : null;
if (!identity || ![identity.policy_sha256, identity.engine_sha256, identity.authority_sha256]
  .every((value) => typeof value === "string" && /^[0-9a-f]{64}$/.test(value))) {
  fail("private RCC identity probe failed");
}

const parsePrevious = (spec) => {
  const separator = spec.lastIndexOf(":");
  if (separator < 1) fail("invalid previous contract");
  const version = spec.slice(0, separator);
  const sha256 = spec.slice(separator + 1);
  if (!/^[A-Za-z0-9._-]{8,96}$/.test(version) || !/^[0-9a-f]{64}$/.test(sha256)) {
    fail("invalid previous contract");
  }
  return { version, sha256 };
};

const current = {
  version: config.executor_contract.version,
  sha256: config.executor_contract.sha256,
};
// Previous contracts are opt-in. A contract whose artifact schema can no
// longer satisfy the evaluator must be rejected at route start, not after a
// provider call has already consumed user capacity.
const executorContracts = [...previousSpecs.map(parsePrevious), current];
if (executorContracts.length > 4 ||
  new Set(executorContracts.map(({ version }) => version)).size !== executorContracts.length ||
  new Set(executorContracts.map(({ sha256 }) => sha256)).size !== executorContracts.length) {
  fail("executor contract rollover must contain 1-4 unique contracts");
}

const executionProfiles = config.execution_profiles;

const output = {
  schema: 4,
  policy_version: policyVersion,
  executor_contracts: executorContracts,
  execution_profiles: executionProfiles,
  maximum_steps: config.maximum_steps,
  rcc: {
    adapter_version: adapterVersion,
    policy_sha256: identity.policy_sha256,
    engine_sha256: identity.engine_sha256,
    authority_sha256: identity.authority_sha256,
  },
};
const serialized = `${JSON.stringify(output)}\n`;
await writeFile(outputPath, serialized, { mode: 0o600 });
const sha256 = createHash("sha256").update(serialized).digest("hex");
process.stdout.write(JSON.stringify({ output: outputPath, bytes: Buffer.byteLength(serialized), sha256 }) + "\n");
