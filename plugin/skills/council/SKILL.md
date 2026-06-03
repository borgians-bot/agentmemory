---
name: council
description: Convene a full council of memory advisors on a topic — six parallel memory queries followed by a deliberation phase that surfaces contradictions, confidence gaps, and a critical synthesis. Use when the user asks a complex question, says "council", "deep dive", "full briefing", or "everything you know about".
argument-hint: "[topic or question]"
user-invocable: true
---

The user wants a council briefing on: $ARGUMENTS

The council has six advisors. Each speaks from a different memory lens. After all advisors report, the council deliberates — surfacing contradictions, unknowns, and a critical verdict.

---

## Phase 1 — Summon the advisors (all six calls in parallel)

1. **The Archivist** — `memory_smart_search { query: "$ARGUMENTS", limit: 10 }`
   Finds the most relevant observations via hybrid BM25 + vector + graph search.

2. **The Historian** — `memory_timeline { anchor: "$ARGUMENTS", before: 8, after: 4 }`
   Reconstructs the chronological arc of events around the topic.

3. **The Analyst** — `memory_patterns { project: "<cwd>" }`
   Reports recurring patterns the agent has noticed across sessions.

4. **The Strategist** — `memory_profile { project: "<cwd>" }`
   Describes the project's top concepts and file landscape.

5. **The Connector** — for the top result returned by the Archivist, call `memory_relations { memoryId: "<top result id>", maxHops: 2, minConfidence: 0.4 }`
   Traces relationships between memories to expose hidden links.
   (If the Archivist returned nothing, skip this advisor and note the absence.)

6. **The Witness** — `memory_sessions` filtered to sessions whose concepts overlap with `$ARGUMENTS` (up to 5 most recent matching sessions), then for each call `memory_recall { query: "$ARGUMENTS", limit: 3 }` scoped to that session.
   Surfaces what past sessions actually did, not just what was recorded as a memory.

---

## Phase 2 — Deliberation (critical thinking, no new tool calls)

Analyze all advisor reports together. For each of the following questions, write one concise answer grounded only in what the tools returned:

1. **Consistency**: Do any two advisors contradict each other? Name the contradiction explicitly (e.g., "The Archivist says X, but the Historian's timeline shows Y").
2. **Confidence**: Which parts of the record are well-evidenced (multiple sources agree) vs. thin (single observation, low importance)? Rate each key claim as `strong`, `moderate`, or `weak`.
3. **Blind spots**: What aspects of `$ARGUMENTS` are completely absent from the record? Name them — absence is evidence.
4. **Evolution**: Did the approach or understanding of this topic change over time? If yes, describe the shift the Historian's timeline reveals.
5. **Hidden links**: What unexpected connections did the Connector expose? Are they meaningful or coincidental?

---

## Phase 3 — Council output

Present the briefing in this order:

**Council Briefing: [topic]**

**Advisor reports**
- Archivist: top observations (group by session, flag importance ≥ 8 as **critical**)
- Historian: key timeline moments (earliest → latest, 3–5 bullet points)
- Analyst: patterns relevant to this topic (drop unrelated ones)
- Strategist: top concepts + files from profile that relate to the query
- Connector: notable memory relationships found (or "no links found")
- Witness: what past sessions actually did about this topic

**Deliberation findings**
- Contradictions (if any)
- Confidence map (strong / moderate / weak per key claim)
- Blind spots (what's missing)
- Evolution of understanding (if the timeline shows a shift)
- Hidden links worth noting

**Verdict**
- 3–5 sentences: the most defensible, evidence-backed answer to `$ARGUMENTS` given everything the council surfaced
- One sentence on what the council still doesn't know

---

**Do NOT invent or hallucinate observations.** Only report what MCP tools returned. If an advisor's tool call fails or returns empty, say so explicitly — empty testimony matters.

If MCP tools are unavailable, fall back to HTTP:
- `POST $AGENTMEMORY_URL/agentmemory/smart-search` → `{"query":"$ARGUMENTS","limit":10}`
- `GET $AGENTMEMORY_URL/agentmemory/sessions`
- `POST $AGENTMEMORY_URL/agentmemory/recall` → `{"query":"$ARGUMENTS","limit":5}`
- Include `Authorization: Bearer $AGENTMEMORY_SECRET` when set.

Tell the user to check `/plugin list` → `agentmemory` enabled, restart Claude Code, and verify `/mcp` shows the agentmemory server connected.
