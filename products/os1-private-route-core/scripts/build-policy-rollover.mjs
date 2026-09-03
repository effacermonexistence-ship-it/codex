#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";

function fail(message) {
  throw new Error(message);
}

const [sourcePath, configPath, outputPath, policyVersion, ...previousSpecs] = process.argv.slice(2);
if (!sourcePath || !configPath || !outputPath || !policyVersion) {
  fail("usage: build-policy-rollover.mjs SOURCE CONFIG OUTPUT POLICY_VERSION [VERSION:SHA256 ...]");
}

const source = JSON.parse(await readFile(sourcePath, "utf8"));
const config = JSON.parse(await readFile(configPath, "utf8"));
if (source?.schema !== 1 || !source.executor_contract || !source.routing || !source.revas) {
  fail("source policy must be a schema-1 policy bundle");
}
if (!config?.executor_contract || !config.model_profiles || !config.effort_profiles) {
  fail("runtime config is missing execution profiles or executor contract");
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

const executionProfiles = Object.fromEntries(["codex", "claude"].map((provider) => [
  provider,
  Object.fromEntries(["standard", "efficient", "deep"].map((tier) => [
    tier,
    {
      model: config.model_profiles[provider]?.[tier],
      effort: config.effort_profiles[provider]?.[tier],
    },
  ])),
]));

const output = {
  schema: 2,
  policy_version: policyVersion,
  executor_contracts: executorContracts,
  execution_profiles: executionProfiles,
  routing: source.routing,
  revas: source.revas,
};
const serialized = `${JSON.stringify(output)}\n`;
await writeFile(outputPath, serialized, { mode: 0o600 });
const sha256 = createHash("sha256").update(serialized).digest("hex");
process.stdout.write(JSON.stringify({ output: outputPath, bytes: Buffer.byteLength(serialized), sha256 }) + "\n");
