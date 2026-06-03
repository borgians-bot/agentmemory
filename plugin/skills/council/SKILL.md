---
name: council
description: Convene a multi-source memory council on a topic — runs smart search, pattern detection, and profile analysis in parallel and synthesizes a comprehensive briefing. Use when the user asks a complex question that benefits from multiple memory perspectives, or says "council", "deep dive", "full briefing", "everything you know about".
argument-hint: "[topic or question]"
user-invocable: true
---

The user wants a council briefing on: $ARGUMENTS

This skill gathers multiple memory perspectives simultaneously and synthesizes them into a single structured briefing.

**Step 1: Parallel queries**

Call these three MCP tools at the same time (do not wait for one before starting the next):

1. `memory_smart_search` — `{ query: "$ARGUMENTS", limit: 8 }` — hybrid BM25 + vector + graph search over all captured observations.
2. `memory_patterns` — `{ project: "<current working directory>" }` — recurring patterns the agent has observed across sessions.
3. `memory_profile` — `{ project: "<current working directory>" }` — top concepts and file patterns for this project.

**Step 2: Follow-up expansion (optional)**

If `memory_smart_search` returned at least 3 results, pick the top 3 and call `memory_recall` once per result using a refined query derived from that result's concepts (limit 5 per call). Run these calls in parallel too.

**Step 3: Synthesize and present**

Present a structured briefing:

---
**Council Briefing: [topic]**

**From the record**
- Observations from `memory_smart_search`, grouped by session
- Show type, title, and narrative for each
- Flag any with importance >= 8 as **critical**

**Recurring patterns**
- Patterns from `memory_patterns` relevant to the topic (skip unrelated ones)

**Project profile snapshot**
- Top concepts and files from `memory_profile` most related to the query

**Synthesis**
- 2–3 sentences tying all three sources together
- Note any gaps, contradictions, or open questions in the record
---

**Do NOT invent or hallucinate observations.** Only surface what the MCP tools returned. If fewer than 2 tools succeed, note which sources are missing and why.

If MCP tools are unavailable, fall back to HTTP:
- `POST $AGENTMEMORY_URL/agentmemory/smart-search` with body `{"query": "$ARGUMENTS", "limit": 8}`
- `GET $AGENTMEMORY_URL/agentmemory/patterns?project=<cwd>`
- Include `Authorization: Bearer $AGENTMEMORY_SECRET` when set.

Tell the user to check `/plugin list` → `agentmemory` enabled, then restart Claude Code and verify `/mcp` shows the agentmemory server connected.
