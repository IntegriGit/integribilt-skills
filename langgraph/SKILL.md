---
name: langgraph
description: >-
  Use when building stateful agents, agent graphs, or multi-actor LLM workflows
  with LangGraph at IntegriBilt — StateGraph, state schemas, nodes, edges,
  conditional routing, Command, Send/fan-out, streaming, checkpointing and
  persistence (thread_id, Postgres, time-travel), long-term memory (Store),
  human-in-the-loop (interrupt/approval pauses/validation loops), the ReAct
  agent pattern, the langgraph CLI (new/dev/build/up/deploy), and wiring runs
  through the self-hosted LiteLLM Gateway on SVR02 with tracing to Langfuse or
  LangSmith. Trigger phrases include "langgraph", "stateful agent", "agent
  graph", "checkpointing", "human-in-the-loop", "interrupt", "react agent",
  "agent workflow", "multi-step agent", "time travel", "subgraph".
---

# LangGraph (IntegriBilt)

Built from the official LangChain skills, consolidated and adapted for IntegriBilt:
- `langgraph-fundamentals` — StateGraph, state/reducers, nodes, edges, Command, Send, streaming, error handling
- `langgraph-persistence` — checkpointers, thread_id, time-travel, Store, subgraph scoping
- `langgraph-human-in-the-loop` — interrupt(), Command(resume=...), approval & validation loops, idempotency
- `langgraph-cli` — new / dev / build / up / deploy / langgraph.json
- `deepagentsjs/langgraph-docs` — live doc-fetching pattern (see References)

Deep material lives in `references/` — pull it in when you need full examples.

---

## Overview

LangGraph models agent workflows as **directed graphs**:

- **StateGraph** — the builder class for a stateful graph.
- **Nodes** — functions that do work and return *partial* state updates.
- **Edges** — define execution order: static (`add_edge`) or conditional (`add_conditional_edges`).
- **START / END** — sentinel nodes marking entry and exit.
- **Reducers** — control how concurrent/sequential state updates merge.

Graphs must be `compile()`d before execution. Use LangGraph when you need fine-grained orchestration, branching/loops, persistence, or human-in-the-loop. For quick stateless calls, plain LangChain is lighter.

### Design methodology (5 steps)

1. **Map discrete steps** — sketch a flowchart; each step becomes a node.
2. **Classify each step** — LLM step, data step, action step, or user-input step. Note static context (prompt), dynamic context (from state), retry strategy, outcome.
3. **Design state** — shared memory for all nodes. Store raw data; format prompts on demand inside nodes.
4. **Build nodes** — each takes `state`, returns a partial-update dict.
5. **Wire it** — connect edges, add routing, compile with a checkpointer if persistence/HITL is needed.

---

## IntegriBilt / LiteLLM Gateway integration

**Always** run LangGraph models through the self-hosted **LiteLLM Gateway on SVR02** — it is OpenAI-compatible at `http://192.168.254.2:4000`. Never call OpenAI/Anthropic/Google directly from agent code; the gateway centralizes keys, model routing, cost accounting, and observability.

- Gateway base URL: `http://192.168.254.2:4000` (use the explicit IP, never `localhost`, for cross-host calls).
- Gateway config: `/srv/core/litellm/config.yaml` on SVR02 (source of truth for which models are exposed).
- Example gateway model names: `gpt-codex-5.6`, `gemini-3.5-pro`, `glm-4.6`. Run `curl -s http://192.168.254.2:4000/v1/models` (with the key) to list what is actually live — model availability changes as `config.yaml` and the model DB change.

### Secrets — BWS only, never hardcoded

The LiteLLM virtual key is a secret. Fetch it at runtime from Bitwarden Secrets Manager:

```bash
export LITELLM_API_KEY="$(bws secret get <LITELLM_VKEY_SECRET_ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
```

> **TODO (fill in):** BWS secret ID for the LangGraph LiteLLM virtual key (`<LITELLM_VKEY_SECRET_ID>`).

Never write the key to disk in cleartext, never echo it into a task log, never paste it into `langgraph.json`. Pass it via environment only.

### Wiring the model (Python)

```python
import os
from langchain_openai import ChatOpenAI

# LITELLM_API_KEY is exported from BWS (see above) — never hardcoded.
llm = ChatOpenAI(
    base_url="http://192.168.254.2:4000",   # LiteLLM Gateway on SVR02
    api_key=os.environ["LITELLM_API_KEY"],   # litellm virtual key from BWS
    model="gpt-codex-5.6",                    # a model exposed by the gateway
    temperature=0,
)

def call_model(state):
    response = llm.invoke(state["messages"])
    return {"messages": [response]}
```

### Wiring the model (TypeScript)

```typescript
import { ChatOpenAI } from "@langchain/openai";

const llm = new ChatOpenAI({
  configuration: { baseURL: "http://192.168.254.2:4000" }, // LiteLLM Gateway on SVR02
  apiKey: process.env.LITELLM_API_KEY,                      // litellm virtual key from BWS
  model: "gemini-3.5-pro",                                  // a gateway model
  temperature: 0,
});
```

For a prebuilt ReAct agent against the gateway, pass the same `llm` to `create_react_agent(llm, tools)` (`langgraph.prebuilt`).

---

## Core: StateGraph, state, nodes, edges

### State and reducers

State is a `TypedDict` (Python) / `StateSchema` (TS). Reducers decide how updates merge.

| Need | Solution |
|------|----------|
| Overwrite value (default) | no reducer |
| Append to list | `Annotated[list, operator.add]` |
| Custom merge | custom reducer function |

```python
from typing_extensions import TypedDict, Annotated
import operator

class State(TypedDict):
    name: str                                  # overwrites on update
    messages: Annotated[list, operator.add]    # appends
    total: Annotated[int, operator.add]        # sums
```

**Rules that bite people:**
- A list field **without** a reducer is *overwritten* — the last write wins and earlier values are lost. Add `operator.add`.
- Nodes return **partial update dicts**, never the mutated full state object.

### Nodes — signatures

| Signature | Use when |
|-----------|----------|
| `def node(state)` | only needs state |
| `def node(state, config: RunnableConfig)` | needs `thread_id`, tags, configurable values |
| `def node(state, runtime: Runtime[Context])` | needs runtime context, `store`, or stream writer |

### Edges

| Need | Edge type |
|------|-----------|
| Always same next node | `add_edge()` |
| Route on state | `add_conditional_edges()` |
| Update state **and** route in one node | return `Command(update=..., goto=...)` |
| Fan-out to parallel workers | return `[Send("worker", {...})]` |

```python
from langgraph.graph import StateGraph, START, END

graph = (
    StateGraph(State)
    .add_node("process", process_input)
    .add_node("finalize", finalize)
    .add_edge(START, "process")
    .add_edge("process", "finalize")
    .add_edge("finalize", END)
    .compile()   # compile before invoking
)
result = graph.invoke({"input": "hello"})
```

- **Command** adds *dynamic* edges only — static `add_edge` edges still fire. If a node returns `Command(goto="c")` **and** you have `add_edge(node, "b")`, both `b` and `c` run.
- **Send** requires a reducer on the results field, or parallel workers overwrite each other.
- `START` is entry-only — never route back to it; use a named entry node.

Full bilingual (Python + TypeScript) examples for basic graphs, conditional edges, `Command`, the `Send` orchestrator-worker pattern, and streaming are in **`references/core-patterns.md`**.

### Streaming

| Mode | Streams | Use for |
|------|---------|---------|
| `values` | full state per step | monitoring |
| `updates` | state deltas | incremental tracking |
| `messages` | LLM tokens + metadata | chat UIs |
| `custom` | user-defined data | progress indicators |

```python
for token, meta in graph.stream({"messages": [...]}, stream_mode="messages"):
    if hasattr(token, "content"):
        print(token.content, end="", flush=True)
```

### Error handling (4-tier)

| Error | Owner | Strategy |
|-------|-------|----------|
| Transient (network, rate limit) | system | `RetryPolicy(max_attempts=3)` on the node |
| LLM-recoverable (tool failure) | LLM | `ToolNode(tools, handle_tool_errors=True)` → error returned as ToolMessage |
| User-fixable (missing info) | human | `interrupt({...})` (see HITL) |
| Unexpected | developer | let it bubble up / `raise` |

---

## Persistence & memory

A **checkpointer** saves graph state at every super-step; a **`thread_id`** identifies one conversation/sequence.

| Checkpointer | Use | Production |
|--------------|-----|-----------|
| `InMemorySaver` | tests/dev | No |
| `SqliteSaver` | local dev | Partial |
| `PostgresSaver` | production | **Yes** |

```python
from langgraph.checkpoint.memory import InMemorySaver

graph = builder.compile(checkpointer=InMemorySaver())
config = {"configurable": {"thread_id": "conversation-1"}}   # ALWAYS pass thread_id
graph.invoke({"messages": ["Hello"]}, config)
graph.invoke({"messages": ["What did I say?"]}, config)       # remembers
```

- **No `thread_id` → no memory.** State only persists when you pass it.
- **Production uses Postgres**, not `InMemorySaver` (data is lost on restart). Run `PostgresSaver(...).setup()` **once at deploy time**, not at app startup. The IntegriBilt stack already runs Postgres on SVR02 — point `DATABASE_URL` at it rather than spinning up a new DB.

> **TODO (fill in as we learn):** the canonical SVR02 Postgres `DATABASE_URL`/DSN for LangGraph checkpoints, and its BWS secret ID.

**Time travel** — browse history and replay or fork from a past checkpoint; **Store** — cross-thread long-term memory (user prefs/facts) via `runtime.store`. `update_state` *passes through* reducers — use `Overwrite(...)` to replace instead of append. Subgraph checkpointer scoping (`False` / `None` / `True`) and parallel-subgraph namespacing are covered in full in **`references/persistence.md`**.

---

## Human-in-the-loop

Pause a graph for human approval/input with `interrupt(value)`, resume with `Command(resume=value)`.

**Requirements:** a checkpointer, a `thread_id`, and a JSON-serializable interrupt payload.

```python
from langgraph.types import interrupt, Command

def approval_node(state):
    approved = interrupt("Do you approve this action?")  # pauses here
    return {"approved": approved}                        # resume value lands here

# Run → pauses; result["__interrupt__"] holds the prompt
result = graph.invoke({"approved": False}, config)
# Resume with the human's answer
result = graph.invoke(Command(resume=True), config)
```

**Critical gotcha — idempotency:** on resume, the node restarts **from the beginning**; all code before `interrupt()` re-runs (in subgraphs, both parent and subgraph nodes re-run). So:
- Use **upsert / check-before-create** before `interrupt()`, never raw inserts or list appends (they duplicate on every resume).
- Prefer placing side effects **after** `interrupt()`, or in their own node.

`Command(resume=...)` is the **only** Command pattern valid as `invoke`/`stream` input — passing `Command(update=...)` as input makes the graph appear stuck. Approval-routing, validation-loop, and multiple-parallel-interrupt examples (with TypeScript) are in **`references/human-in-the-loop.md`**.

---

## CLI & deploy

The `langgraph` CLI manages the lifecycle; all commands except `new` read `langgraph.json`.

```bash
pip install 'langgraph-cli[inmem]'   # includes the dev server

langgraph new ./my-agent              # scaffold from template
langgraph dev                         # local hot-reload server, no Docker (port 2024)
langgraph up --recreate               # production-like Docker stack + Postgres (port 8123)
langgraph build -t my-agent-image     # build a Docker image
langgraph deploy --name my-agent      # ship to LangGraph Platform
langgraph deploy logs -f              # tail runtime logs
```

Minimal `langgraph.json`:

```json
{
  "dependencies": ["."],
  "graphs": { "agent": "./my_agent/agent.py:graph" },
  "env": "./.env"
}
```

**IntegriBilt deploy posture:** for self-hosted runs, prefer `langgraph up` on the Docker stack over LangGraph Platform — it keeps state on SVR02 Postgres and stays inside our network. `langgraph deploy` (LangGraph Platform / LangSmith Deployments) requires `LANGSMITH_API_KEY` and ships off-network; only use it deliberately. Keep all keys (`LITELLM_API_KEY`, `DATABASE_URL`, tracing keys) in `.env` populated from BWS at deploy time — never commit them. Full command/flag reference and `langgraph.json` key table are in **`references/cli.md`**.

> **TODO (fill in as we learn):** whether IntegriBilt standardizes on `langgraph up` against the shared SVR02 stack vs LangGraph Platform, and the target compose profile.

---

## Observability

Trace every LangGraph run so we can debug agents and watch cost. Two backends, both cross-linked to sibling skills in this repo.

### Langfuse (self-hosted, preferred)

Langfuse runs in the IntegriBilt stack and pairs naturally with the LiteLLM Gateway. Wire it via the OpenTelemetry/callback integration; keys come from BWS.

```bash
export LANGFUSE_PUBLIC_KEY="$(bws secret get <LANGFUSE_PUBLIC_KEY_ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGFUSE_SECRET_KEY="$(bws secret get <LANGFUSE_SECRET_KEY_ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGFUSE_HOST="http://192.168.254.2:3000"   # confirm actual host/port
```

```python
from langfuse.langchain import CallbackHandler

langfuse_handler = CallbackHandler()
graph.invoke(inputs, config={"callbacks": [langfuse_handler],
                             "configurable": {"thread_id": "t1"}})
```

LiteLLM can *also* forward generations to Langfuse at the gateway layer (`/srv/core/litellm/config.yaml`), giving you traces even for non-LangGraph callers. See the sibling **`langfuse`** skill in this repo for setup, dashboards, and the gateway-side config.

> **TODO (fill in):** BWS secret IDs for `LANGFUSE_PUBLIC_KEY` / `LANGFUSE_SECRET_KEY`, and the confirmed Langfuse host:port on SVR02.
> **TODO (fill in as we learn):** create the sibling `langfuse` skill if not yet present.

### LangSmith (hosted, optional)

LangSmith auto-traces LangGraph when env vars are set — useful with LangGraph Platform deploys.

```bash
export LANGSMITH_TRACING=true
export LANGSMITH_API_KEY="$(bws secret get <LANGSMITH_API_KEY_ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGSMITH_PROJECT="integribilt-langgraph"
```

It is a hosted SaaS (data leaves our network) — prefer Langfuse for internal work; use LangSmith when deploying to LangGraph Platform. See the sibling **`langsmith`** skill.

> **TODO (fill in):** BWS secret ID for `LANGSMITH_API_KEY`.
> **TODO (fill in as we learn):** create the sibling `langsmith` skill if not yet present.

---

## Anti-patterns & gotchas

- **Hardcoding model keys / pointing at provider APIs directly.** Always go through the LiteLLM Gateway (`http://192.168.254.2:4000`) with a BWS-sourced virtual key.
- **Using `localhost` for cross-host calls.** Use explicit IPs (`192.168.254.2`).
- **Mutating state in a node** instead of returning a partial-update dict.
- **List field without a reducer** → updates overwrite instead of append.
- **Forgetting `compile()`** → `builder.invoke(...)` fails.
- **Routing back to `START`** → it is entry-only.
- **`Command(goto=...)` while a static `add_edge` also exists** → both targets run.
- **`Send` fan-out without a reducer on the results field** → last worker wins.
- **Infinite loops** — a cyclic graph needs a conditional edge to `END`.
- **No `thread_id`** → no persistence and HITL resume goes to the wrong thread.
- **`InMemorySaver` in production** → state lost on restart; use `PostgresSaver`.
- **Non-idempotent side effects before `interrupt()`** → duplicated on every resume.
- **Passing `Command(update=...)` as invoke input** → graph appears stuck; only `Command(resume=...)` is valid input.
- **Committing secrets into `langgraph.json` / `.env`** → populate `.env` from BWS at deploy time only.

---

## Troubleshooting

| Symptom | Likely cause | Cheapest check / fix |
|---------|--------------|----------------------|
| `AttributeError`/no `invoke` on builder | forgot `compile()` | `graph = builder.compile()` |
| Earlier list values disappear | missing reducer | add `Annotated[list, operator.add]` |
| Agent "forgets" across turns | no `thread_id` | pass `{"configurable": {"thread_id": "..."}}` |
| State lost after restart | `InMemorySaver` | switch to `PostgresSaver` on SVR02 |
| Two nodes run when one expected | `Command(goto)` + static edge both present | drop the static edge or the goto |
| Parallel worker results clobbered | no reducer on results | add `operator.add` reducer |
| Graph "stuck" / re-runs forever after interrupt | passed `Command(update=...)` or wrong `thread_id` | resume with `Command(resume=...)` and the same `thread_id` |
| Duplicate DB rows after a human approval | non-idempotent op before `interrupt()` | upsert, or move side effect after `interrupt()` |
| `401`/auth error to model | bad/missing LiteLLM virtual key | re-fetch from BWS; verify against `curl http://192.168.254.2:4000/v1/models` |
| `Connection refused` to gateway | wrong host or down | use `192.168.254.2:4000` (not localhost); check the LiteLLM container on SVR02 |
| No traces appearing | tracing env/callback not wired | set Langfuse/LangSmith env from BWS; attach callback or enable `LANGSMITH_TRACING` |

For deeper LangGraph behavior questions, fetch live docs: read `https://docs.langchain.com/llms.txt` for the index, then fetch the 2–4 most relevant URLs (pattern from `deepagentsjs/langgraph-docs`). Details in **`references/doc-fetching.md`**.

---

## References

- `references/core-patterns.md` — full Python + TypeScript examples: basic graph, conditional edges, Command, Send orchestrator/worker, streaming modes, error handling, common fixes.
- `references/persistence.md` — checkpointer setup, Postgres, threads, time-travel/fork, Store/long-term memory, subgraph checkpointer scoping & parallel namespacing.
- `references/human-in-the-loop.md` — interrupt/resume, approval routing, validation loops, multiple parallel interrupts, idempotency rules.
- `references/cli.md` — every `langgraph` command + flags, `langgraph.json` key reference, `dev` vs `up`, gotchas.
- `references/doc-fetching.md` — the live LangGraph documentation-fetching workflow.
