#!/bin/bash
# SessionStart hook for Claude Code on the web.
# Installs deps, builds agentmemory, and launches the memory server in the
# background so the agentmemory hooks/MCP can reach it on :3111. Idempotent.
set -euo pipefail

# Only run in the remote (Claude Code on the web) environment.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-/home/user/agentmemory}"

# 1. Dependencies (npm install benefits from container-state caching).
#    --legacy-peer-deps mirrors CI: tsdown wants typescript ^5 but the repo
#    pins typescript ^6, so a strict resolve (ERESOLVE) fails otherwise.
if [ ! -d node_modules ]; then
  npm install --legacy-peer-deps --no-audit --no-fund
fi

# 2. Build the worker/CLI/hooks bundles into dist/ and plugin/scripts/.
if [ ! -f dist/cli.mjs ]; then
  npm run build
fi

# 3. Start the agentmemory server in the background if not already up.
#    The CLI bootstraps a pinned iii-engine then spawns the worker, which
#    binds the REST API on :3111. Detached + nohup so it survives the hook.
if ! curl -fsS -o /dev/null "http://localhost:3111/agentmemory/health" 2>/dev/null; then
  mkdir -p .agentmemory-logs
  nohup node dist/cli.mjs > .agentmemory-logs/server.log 2>&1 &
  disown || true
fi

echo "agentmemory session-start hook complete"
