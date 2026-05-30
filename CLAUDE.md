# CLAUDE.md

Guidance for Claude Code (and other AI assistants) working in this repository.

> This repo already has an authoritative agent guide in **[AGENTS.md](./AGENTS.md)**
> and a human contributor guide in **[CONTRIBUTING.md](./CONTRIBUTING.md)**. This
> file is the orientation layer: read it first, then defer to `AGENTS.md` for the
> exact **consistency rules** (the lists of files that must change together) and to
> `CONTRIBUTING.md` for the PR/release process. When those documents disagree with
> this one, they win — and update this file to match.

## What this is

`@agentmemory/agentmemory` is **persistent memory for AI coding agents**. It runs a
local memory server that captures an agent's sessions (via hooks), stores them, and
serves recall back over MCP, a REST API, and a web viewer — so agents like Claude
Code, Codex, Cursor, Copilot, Gemini CLI, etc. stop re-explaining context.

It is built on **iii-engine's three primitives**: **Worker / Function / Trigger**.
Everything goes through `sdk.registerFunction()` / `sdk.registerTrigger()` /
`sdk.trigger()`. **Never** bypass iii-engine with a standalone SQLite client or an
in-process store — state lives in iii-engine's file-based SQLite StateModule
(`./data/state_store.db`), reached over a WebSocket to the engine (default port
`49134`).

- **Language/runtime:** TypeScript, **ESM only** (`"type": "module"`), Node `>=20`.
- **Build:** `tsdown` → ESM bundles in `dist/`.
- **Tests:** `vitest`.
- **Default ports:** REST API `:3111`, streams `:3112`, viewer `:3113` (`restPort + 2`).

## Commands

```bash
npm install                 # Node >=20. Note: lockfiles are gitignored (see below).
npm run build               # tsdown bundle + copy iii-config/viewer assets into dist/
npm run dev                 # run the worker directly via tsx (src/index.ts)
npm start                   # run the built CLI (node dist/cli.mjs)

npm test                    # vitest, EXCLUDES test/integration.test.ts (the default gate)
npm run test:watch          # vitest watch (same exclusion)
npm run test:integration    # only integration.test.ts — needs a live server on :3111
npm run test:all            # everything, including integration

npm run bench:load          # load benchmark (100k)
npm run eval:longmemeval    # LongMemEval eval runner
npm run eval:coding-life    # coding-agent-life eval runner
```

Before any PR: `npm run build` must compile clean **and** `npm test` must pass
(950+ tests). The single `test/integration.test.ts` needs a live server and is fine
to skip locally.

### Running the CLI

The built binary is `agentmemory` (`bin` → `dist/cli.mjs`). Common subcommands:
`agentmemory` (start the server), `agentmemory connect <agent>` (wire hooks/MCP into
Claude Code, Codex, Cursor, Copilot, Gemini CLI, …), `agentmemory status`,
`agentmemory doctor`, `agentmemory demo`. The CLI bootstraps a pinned iii-engine
(`AGENTMEMORY_III_VERSION`, default `0.11.2`) and spawns the worker.

## Architecture map

The worker boots in `src/index.ts:160` (`main()`): it loads config, builds the LLM
and embedding providers, opens the KV store, then calls every `registerXFunction()`
in turn, wires REST/MCP/event triggers, starts the viewer, restores persisted
indexes, and starts background sweeps (auto-forget, consolidation, decay).

| Path | What lives here |
|------|-----------------|
| `src/index.ts` | Worker entry point. Registers all functions/triggers and starts the server. |
| `src/cli.ts` | CLI: engine bootstrap, `connect`, `status`, `doctor`, onboarding, lifecycle. |
| `src/config.ts` | Env-driven config + feature-flag helpers (`isXEnabled()`, `loadXConfig()`). |
| `src/functions/` | The core memory operations (63 modules). Each exports `registerXFunction(sdk, kv, …)`. e.g. `observe`, `remember`, `search`, `smart-search`, `compress`, `consolidate`, `reflect`, `graph`, `retention`, `governance`, `export-import`, plus the orchestration layer (`actions`, `frontier`, `leases`, `routines`, `signals`, `checkpoints`, `mesh`, `crystallize`, …). |
| `src/state/` | Storage + indexes: `kv.ts` (`StateKV` over iii-engine), `schema.ts` (KV scope keys + `generateId`/`fingerprintId`/`jaccardSimilarity`), `vector-index.ts`, `search-index.ts` (BM25), `hybrid-search.ts` (BM25 + vector + graph), `index-persistence.ts`, `reranker.ts`, `keyed-mutex.ts`. |
| `src/providers/` | LLM providers (`anthropic`, `openai`, `minimax`, `openrouter`, `agent-sdk`, `noop`) + resilience (`resilient`, `fallback-chain`, `circuit-breaker`). `embedding/` holds embedding providers (voyage, openai, gemini, cohere, openrouter, clip, local). |
| `src/mcp/` | MCP surface: `server.ts` (REST-backed `mcp::tools::*`), `tools-registry.ts` (tool defs + visibility), `standalone.ts` (the `@agentmemory/mcp` package, runs without iii-engine), `transport.ts`, `rest-proxy.ts`, `in-memory-kv.ts`. |
| `src/triggers/` | `api.ts` registers every `/agentmemory/*` REST endpoint; `events.ts` registers stream listeners. |
| `src/hooks/` | Standalone Node scripts (no iii-sdk import) that agents invoke on lifecycle events; they read JSON from stdin and call the REST API. See the two hook patterns below. |
| `src/prompts/` | LLM prompt templates (compression, consolidation, graph-extraction, reflect, summary, vision, xml). |
| `src/eval/`, `eval/` | Offline quality/eval harness (`metrics-store`, `quality`, `validator`, `self-correct`) and runners/datasets. |
| `src/health/` | Liveness/readiness + alert thresholds. |
| `src/replay/` | Claude Code JSONL transcript parsing + timeline reconstruction (`import-jsonl`). |
| `src/viewer/` | Web UI server + HTML for the real-time viewer. |
| `src/telemetry/` | OpenTelemetry metric/trace setup. |
| `src/cli/connect/` | Per-agent adapters (claude-code, codex, cursor, copilot-cli, gemini-cli, zed, cline, continue, …). |
| `plugin/` | The Claude Code / Codex / Copilot plugin: `plugin.json`, `hooks/*.json`, `scripts/*.mjs` (built from `src/hooks/`), `skills/` (8 native skills: remember, recall, forget, recap, handoff, session-history, commit-context, commit-history). |
| `integrations/` | First-party plugins: `hermes/`, `openclaw/`, `pi/`, `filesystem-watcher/`. |
| `packages/mcp/` | Thin npm wrapper that ships the standalone MCP server. |
| `website/` | Marketing site (Next.js). `DESIGN.md` is this site's design system, **not** the engine architecture. |
| `test/` | Vitest suite (one `*.test.ts` per feature). |
| `benchmark/`, `docs/`, `deploy/` | Benchmarks, docs/benchmark scorecards, container deploy recipes (fly/render/coolify/railway). |

### Data model

KV scopes are defined in `src/state/schema.ts` (the `KV` object). Highlights:
`mem:sessions`, `mem:obs:{sessionId}` (per-session observations), `mem:memories`
(long-term, versioned), `mem:summaries`, `mem:graph:nodes` / `mem:graph:edges`,
`mem:relations`, `mem:index:bm25`, team scopes (`mem:team:{teamId}:*`), `mem:audit`,
plus the orchestration scopes (`mem:actions`, `mem:leases`, `mem:routines`,
`mem:signals`, `mem:checkpoints`, …). In-memory BM25 + vector indexes are snapshotted
to disk via `IndexPersistence` and restored on boot (with a dimension-mismatch guard
— see `src/index.ts:394`).

## Conventions

From `AGENTS.md` and `CONTRIBUTING.md` — follow these:

- **ESM only**, TypeScript **strict**. No `any` without a justifying comment.
- **No comments that restate the code.** Only comment the *why* — a hidden
  constraint, invariant, or bug workaround. Prefer clear naming over narration.
- IDs: `fingerprintId()` for content-addressable dedup, `generateId()` for unique IDs.
- Parallelize independent KV reads/writes with `Promise.all`.
- Validate inputs at system boundaries (MCP handlers, REST endpoints). REST
  endpoints must **whitelist fields** — never pass a raw request body to
  `sdk.trigger()`.
- Record state-changing operations with `recordAudit()`.
- Capture a timestamp once (`new Date().toISOString()`) and reuse it.
- Tests live in `test/<feature>.test.ts`, named after behavior not implementation.
  Mock the engine with `vi.mock("iii-sdk")` and a fake `sdk.trigger` / `kv`.
  Follow an existing function test (e.g. `test/crystallize.test.ts`) for shape.

### Hook script patterns (`src/hooks/`)

Hook scripts are standalone (no iii-sdk); they read stdin and call the REST API.
Two patterns — get this right or hooks hang the agent:

- **Context-injecting** (`session-start`, `pre-tool-use`, `pre-compact`) write
  recalled context to stdout, so they must `await fetch(..., { signal:
  AbortSignal.timeout(N) })` inside try/catch.
- **Telemetry-only** (the rest) write nothing to stdout. Use fire-and-forget
  `fetch(...).catch(() => {})` paired with `setTimeout(() => process.exit(0),
  500).unref()` (1500ms for multi-request hooks like `stop`/`session-end`).
  Without the `unref`'d timeout, Node keeps the loop alive and the hook blocks the
  agent's next prompt.

### Consistency rules (read AGENTS.md before these changes)

Some changes must touch several files in lockstep, or counts/tests drift:

- **Adding/removing an MCP tool** → update the function (`src/functions/`),
  `src/triggers/api.ts` (REST twin), `src/mcp/tools-registry.ts`, `src/mcp/server.ts`
  (handler), `src/mcp/standalone.ts` (if exposed there), `src/index.ts` (counts),
  the tool-count tests/README/plugin manifests. Add a `test/`.
- **Adding a REST endpoint** → `src/triggers/api.ts` + endpoint count in
  `src/index.ts` + README.
- **Adding an auto-hook** → add the `HookType` to `src/types.ts`, wire
  `src/hooks/<name>.ts`, add it to `tsdown.config.ts` hook entries, add a test.
- **Adding a KV scope** → `src/state/schema.ts` + the interface in `src/types.ts`.
- **Version bump** is a release task that touches ~8 files in lockstep
  (`package.json`, `src/version.ts`, `src/types.ts`, `src/functions/export-import.ts`,
  `test/export-import.test.ts`, plugin manifests, …). See `CONTRIBUTING.md`.

`AGENTS.md` carries the exact, current file lists — consult it, don't trust this
summary's completeness.

## Build, CI & git

- `tsdown.config.ts` produces: `dist/index.mjs` (worker, with shebang + dts),
  `dist/cli.mjs`, `dist/standalone.mjs`, and one bundle per hook into both
  `dist/hooks/` and `plugin/scripts/`. `@xenova/transformers` and the
  `onnxruntime-*` packages are kept external (lazy-loaded optionalDependencies).
- **Lockfiles are gitignored** (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`)
  — never commit them. CI generates a lockfile in-runner (`npm install
  --package-lock-only`) then `npm ci`. So is `data/` and `dist/`.
- **CI** (`.github/workflows/ci.yml`): matrix of ubuntu + macOS × Node 20/22, running
  `build` then `test`. Doc-only / `website/**` / `assets/**` changes are skipped via
  `paths-ignore`.
- **Branches:** features branch off `main` (`feat/…`, `fix/…`, `docs/…`,
  `refactor/…`, `chore/…`). Keep PRs small and focused.
- **Commits:** the upstream project requires **DCO sign-off** (`git commit -s`) and
  **forbids attribution headers** ("Generated with Claude Code", "Co-Authored-By:
  Claude", etc.) in commits and PR descriptions. Don't add them.
- CHANGELOG is touched only in release PRs, not feature PRs.
