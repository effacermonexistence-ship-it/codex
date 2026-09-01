import { createHash } from "node:crypto";
import { lstat, readFile, readdir } from "node:fs/promises";
import { basename, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const moduleDirectory = resolve(fileURLToPath(new URL(".", import.meta.url)));
const defaultPolicyPath = resolve(
  moduleDirectory,
  "../security/client-artifact-scan-policy.json",
);

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function shannonEntropy(value) {
  const counts = new Map();
  for (const character of value) {
    counts.set(character, (counts.get(character) ?? 0) + 1);
  }
  let entropy = 0;
  for (const count of counts.values()) {
    const probability = count / value.length;
    entropy -= probability * Math.log2(probability);
  }
  return entropy;
}

function printableStrings(bytes) {
  const output = [];
  let current = "";
  let start = 0;
  for (let index = 0; index <= bytes.length; index += 1) {
    const byte = bytes[index];
    if (byte !== undefined && byte >= 32 && byte <= 126) {
      if (current.length === 0) start = index;
      current += String.fromCharCode(byte);
      continue;
    }
    if (current.length >= 8) output.push({ offset: start, value: current });
    current = "";
  }
  return output;
}

async function collectFiles(target, root = target) {
  const metadata = await lstat(target);
  if (metadata.isSymbolicLink()) {
    return [{ path: target, relativePath: relative(root, target), symlink: true }];
  }
  if (metadata.isFile()) {
    return [{ path: target, relativePath: relative(root, target) || basename(target), symlink: false }];
  }
  if (!metadata.isDirectory()) return [];
  const entries = await readdir(target, { withFileTypes: true });
  const nested = await Promise.all(
    entries.map((entry) => collectFiles(join(target, entry.name), root)),
  );
  return nested.flat();
}

export async function loadPolicy(path = defaultPolicyPath) {
  const value = JSON.parse(await readFile(path, "utf8"));
  if (
    !Array.isArray(value.forbiddenPathFragments) ||
    !Array.isArray(value.forbiddenContentFragments) ||
    typeof value.entropy?.minimumLength !== "number" ||
    typeof value.entropy?.minimumBitsPerCharacter !== "number" ||
    !Array.isArray(value.entropy?.allowedTokenSha256)
  ) {
    throw new Error("invalid scan policy");
  }
  return value;
}

export async function scanClientArtifacts(targets, policy) {
  const selectedPolicy = policy ?? (await loadPolicy());
  if (!Array.isArray(targets) || targets.length === 0) {
    throw new Error("at least one explicit client artifact path is required");
  }
  const roots = targets.map((target) => resolve(target));
  const fileGroups = await Promise.all(roots.map((target) => collectFiles(target)));
  const files = fileGroups.flat();
  if (files.length === 0) throw new Error("no client artifact files found");

  const findings = [];
  const allowedEntropy = new Set(selectedPolicy.entropy.allowedTokenSha256);
  for (const file of files) {
    const label = file.relativePath || basename(file.path);
    if (file.symlink) {
      findings.push({ kind: "symlink", file: label });
      continue;
    }
    const lowerPath = label.toLowerCase();
    for (const fragment of selectedPolicy.forbiddenPathFragments) {
      if (lowerPath.includes(String(fragment).toLowerCase())) {
        findings.push({ kind: "forbidden_path", file: label, fingerprint: sha256(String(fragment)) });
      }
    }

    const bytes = await readFile(file.path);
    for (const item of printableStrings(bytes)) {
      for (const fragment of selectedPolicy.forbiddenContentFragments) {
        if (item.value.toLowerCase().includes(String(fragment).toLowerCase())) {
          findings.push({
            kind: "forbidden_content",
            file: label,
            offset: item.offset,
            fingerprint: sha256(String(fragment)),
          });
        }
      }
      const candidates = item.value.match(/[A-Za-z0-9_+/=-]{48,}/gu) ?? [];
      for (const candidate of candidates) {
        const fingerprint = sha256(candidate);
        if (
          candidate.length >= selectedPolicy.entropy.minimumLength &&
          shannonEntropy(candidate) >= selectedPolicy.entropy.minimumBitsPerCharacter &&
          !allowedEntropy.has(fingerprint)
        ) {
          findings.push({
            kind: "high_entropy",
            file: label,
            offset: item.offset,
            fingerprint,
          });
        }
      }
    }
  }
  return { filesScanned: files.length, findings };
}

async function main() {
  const policyPath = process.env.OS1_CLIENT_SCAN_POLICY_PATH;
  const policy = policyPath ? await loadPolicy(resolve(policyPath)) : undefined;
  const result = await scanClientArtifacts(process.argv.slice(2), policy);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (result.findings.length > 0) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
