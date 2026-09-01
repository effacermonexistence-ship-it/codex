#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

function git(cwd, args, fallback = null) {
  try {
    return execFileSync("git", args, {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return fallback;
  }
}

function allowedRemoteNames(cwd) {
  const names = (git(cwd, ["remote"], "") || "").split("\n").filter(Boolean);
  return names.filter((name) => {
    const urls = git(cwd, ["remote", "get-url", "--all", name], "") || "";
    return urls
      .split("\n")
      .some((url) =>
        /github\.com(?::|\/)(?:effacermonexistence|effacermonexistence-ship-it)\//.test(
          url,
        ),
      );
  });
}

function snapshot(cwd) {
  const repoRoot = git(cwd, ["rev-parse", "--show-toplevel"]);
  if (!repoRoot) return null;
  const remotes = allowedRemoteNames(repoRoot);
  if (remotes.length === 0) return null;
  return {
    repoRoot,
    remotes,
    head: git(repoRoot, ["rev-parse", "HEAD"]),
    branch: git(repoRoot, ["branch", "--show-current"], ""),
    status: git(repoRoot, ["status", "--porcelain=v1", "--untracked-files=normal"], ""),
  };
}

function digest(value) {
  return crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function stateFile(sessionId) {
  const safeId = /^[A-Za-z0-9._-]+$/.test(sessionId ?? "")
    ? sessionId
    : digest(sessionId ?? "unknown");
  const stateDirectory = path.join(os.homedir(), ".claude", "hook-state");
  fs.mkdirSync(stateDirectory, { recursive: true, mode: 0o700 });
  return path.join(stateDirectory, `remote-backup-${safeId}.json`);
}

function readState(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

function writeState(filePath, state) {
  fs.writeFileSync(filePath, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
}

function block(filePath, state, current, reason) {
  const currentDigest = digest(current);
  const blockCount =
    state.lastBlockedDigest === currentDigest ? (state.blockCount ?? 1) + 1 : 1;
  if (blockCount > 3) return;
  writeState(filePath, {
    ...state,
    lastBlockedDigest: currentDigest,
    blockCount,
  });
  console.error(reason);
  process.exit(2);
}

let input;
try {
  input = JSON.parse(fs.readFileSync(0, "utf8"));
} catch {
  process.exit(0);
}

const filePath = stateFile(input.session_id);

if (input.hook_event_name === "SessionEnd") {
  try {
    fs.unlinkSync(filePath);
  } catch {}
  process.exit(0);
}

if (input.hook_event_name === "SessionStart") {
  const baseline = snapshot(input.cwd);
  if (!baseline) process.exit(0);
  writeState(filePath, { baseline, lastBlockedDigest: null, blockCount: 0 });
  console.log(
    "Remote completion guard is active for this trusted GitHub repository. " +
      "If this session changes the repository, do not stop with uncommitted or unpushed work. " +
      "A fork push and upstream/R2 completion must be reported separately.",
  );
  process.exit(0);
}

if (input.hook_event_name !== "Stop") process.exit(0);
if (Array.isArray(input.background_tasks) && input.background_tasks.length > 0) {
  process.exit(0);
}

const state = readState(filePath);
const current = snapshot(input.cwd);
if (!state?.baseline || !current || current.repoRoot !== state.baseline.repoRoot) {
  process.exit(0);
}

const changedThisSession =
  current.head !== state.baseline.head || current.status !== state.baseline.status;
if (!changedThisSession) process.exit(0);

if (current.status) {
  block(
    filePath,
    state,
    current,
    "This Claude session changed a trusted GitHub repository, but the worktree still has " +
      "uncommitted changes. Review the full diff, run tests and a secret scan, commit the " +
      "authorized changes, then push them to GitHub before stopping. Preserve unrelated user changes.",
  );
  process.exit(0);
}

if (current.head !== state.baseline.head) {
  const containingRefs =
    git(
      current.repoRoot,
      ["branch", "-r", "--contains", current.head, "--format=%(refname:short)"],
      "",
    ) || "";
  const pushed = containingRefs
    .split("\n")
    .filter(Boolean)
    .some((refName) =>
      current.remotes.some((remote) => refName.startsWith(`${remote}/`)),
    );

  if (!pushed) {
    block(
      filePath,
      state,
      current,
      "This Claude session created a local commit that is not present on an allowed GitHub " +
        "remote. Inspect GitHub permissions, push upstream when allowed or push to the authenticated " +
        "fork and create/update a pull request. Then verify or accurately report the R2 manifest state.",
    );
  }
}
