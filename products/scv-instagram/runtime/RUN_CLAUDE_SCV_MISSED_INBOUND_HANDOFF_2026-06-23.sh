#!/usr/bin/env bash
set -euo pipefail
REPO="/Users/REDACTED/PRIVATE_PATH"
FILES_DIR="$REPO/codex_vault/restored_materials/SCV_INSTAGRAM_AUTOMATION_LONG_IDEA_RECOVERY_LOCK_V42_2026-06-21/files"
HANDOFF="$FILES_DIR/CLAUDE_HANDOFF_SCV_MISSED_INBOUND_AUDIT_2026-06-23.md"
cd "$FILES_DIR"
exec /Users/REDACTED/PRIVATE_PATH \
  --name "SCV missed inbound audit handoff" \
  --permission-mode plan \
  --add-dir "$REPO" \
  "$(cat "$HANDOFF")

Start by reading the handoff. Do not edit yet. First produce a concrete implementation plan with exact files, tests, and verification commands. The core objective is: no real inbound may be silently lost."
