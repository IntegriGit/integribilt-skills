# Persistence & memory — checkpointers, threads, time-travel, Store, subgraphs

Built from `langgraph-persistence`.

- **Short-term** (checkpointer): thread-scoped conversation history.
- **Long-term** (store): cross-thread user preferences/facts.

| Checkpointer | Use | Production |
|--------------|-----|-----------|
| `InMemorySaver` | testing/dev | No |
| `SqliteSaver` | local dev | Partial |
| `PostgresSaver` | production | Yes |

> IntegriBilt: use the existing SVR02 Postgres for production checkpoints rather than a new DB.
> **TODO (fill in as we learn):** SVR02 Postgres DSN for LangGraph checkpoints + its BWS secret ID.

## Basic persistence

```python
from langgraph.checkpoint.memory import InMemorySaver

graph = builder.compile(checkpointer=InMemorySaver())
config = {"configurable": {"thread_id": "conversation-1"}}   # ALWAYS provide thread_id
graph.invoke({"messages": ["Hello"]}, config)
graph.invoke({"messages": ["How are you?"]}, config)         # previous + new
```

```typescript
import { MemorySaver } from "@langchain/langgraph";

const graph = builder.compile({ checkpointer: new MemorySaver() });
const config = { configurable: { thread_id: "conversation-1" } };
await graph.invoke({ messages: [new HumanMessage("Hello")] }, config);
```

## Production Postgres

```python
import os
from langgraph.checkpoint.postgres import PostgresSaver

# Run ONCE at deploy time, not at app startup:
#   PostgresSaver.from_conn_string(os.environ["DATABASE_URL"]).setup()
with PostgresSaver.from_conn_string(os.environ["DATABASE_URL"]) as checkpointer:
    graph = builder.compile(checkpointer=checkpointer)
```

```typescript
import { PostgresSaver } from "@langchain/langgraph-checkpoint-postgres";
// await PostgresSaver.fromConnString(process.env.DATABASE_URL!).setup();  // once
const checkpointer = PostgresSaver.fromConnString(process.env.DATABASE_URL!);
const graph = builder.compile({ checkpointer });
```

`DATABASE_URL` should come from BWS at deploy time — never hardcoded.

## Threads are isolated

```python
graph.invoke({"messages": ["Hi from Alice"]}, {"configurable": {"thread_id": "user-alice"}})
graph.invoke({"messages": ["Hi from Bob"]},   {"configurable": {"thread_id": "user-bob"}})
# Alice's state is isolated from Bob's
```

## Time travel — history, replay, fork

```python
config = {"configurable": {"thread_id": "session-1"}}
graph.invoke({"messages": ["start"]}, config)

states = list(graph.get_state_history(config))   # browse checkpoints
past = states[-2]
graph.invoke(None, past.config)                  # None = replay from checkpoint

fork_config = graph.update_state(past.config, {"messages": ["edited"]})
graph.invoke(None, fork_config)                  # fork: edit a past checkpoint, then resume
```

```typescript
const states = [];
for await (const s of graph.getStateHistory(config)) states.push(s);
const past = states[states.length - 2];
await graph.invoke(null, past.config);                       // replay
const forkConfig = await graph.updateState(past.config, { messages: ["edited"] });
await graph.invoke(null, forkConfig);                        // fork
```

`update_state` **passes through reducers** (appends). To replace, use `Overwrite`:

```python
from langgraph.types import Overwrite
graph.update_state(config, {"items": ["C"]})              # ["A","B","C"] — appended
graph.update_state(config, {"items": Overwrite(["C"])})   # ["C"] — replaced
```

## Subgraph checkpointer scoping

| Feature | `checkpointer=False` | `None` (default) | `True` |
|---------|----------------------|------------------|--------|
| Interrupts (HITL) | No | Yes | Yes |
| Multi-turn memory | No | No | Yes |
| Multiple calls (different subgraphs) | Yes | Yes | Warning (namespace conflicts) |
| Multiple calls (same subgraph) | Yes | Yes | No |
| State inspection | No | Warning (current invocation only) | Yes |

- **`False`** — no interrupts/persistence needed; simplest, no overhead.
- **`None`** (omit) — needs `interrupt()` but not cross-invocation memory; each call starts fresh but can pause/resume; parallel-safe (unique namespace per invocation).
- **`True`** — needs to remember state across invocations (multi-turn). Each call resumes where the last left off.

```python
subgraph = subgraph_builder.compile(checkpointer=False)   # no interrupts
subgraph = subgraph_builder.compile()                     # interrupts, no cross-invocation memory
subgraph = subgraph_builder.compile(checkpointer=True)    # stateful across invocations
```

**Warning:** a stateful subgraph (`checkpointer=True`) cannot be called multiple times within one node — same namespace, conflict.

### Parallel subgraph namespacing

When multiple **different** stateful subgraphs run in parallel, wrap each in its own `StateGraph` with a unique node name for stable namespace isolation:

```python
from langgraph.graph import MessagesState, StateGraph

def create_sub_agent(model, *, name, **kwargs):
    agent = create_agent(model=model, name=name, **kwargs)
    return (
        StateGraph(MessagesState)
        .add_node(name, agent)        # unique name -> stable namespace
        .add_edge("__start__", name)
        .compile()
    )
```

Subgraphs added as nodes via `add_node` already get name-based namespaces automatically — no wrapper needed.

## Long-term memory (Store)

```python
from langgraph.store.memory import InMemoryStore
from langgraph.runtime import Runtime

store = InMemoryStore()
store.put(("alice", "preferences"), "language", {"preference": "short responses"})

def respond(state, runtime: Runtime):
    prefs = runtime.store.get((state["user_id"], "preferences"), "language")
    return {"response": f"Using preference: {prefs.value}"}

graph = builder.compile(checkpointer=checkpointer, store=store)  # compile with BOTH
```

Store ops: `put` / `get` / `search(..., filter={...})` / `delete`. Access the store via `runtime.store` inside nodes — never reference a module-level `store` directly.

### Boundaries — do NOT

- Use `InMemorySaver` in production (data lost on restart) — use `PostgresSaver`.
- Forget `thread_id` — state won't persist.
- Expect `update_state` to bypass reducers — use `Overwrite` to replace.
- Run the same stateful subgraph in parallel within one node — namespace conflict.
- Reference a global `store` in a node — use `runtime.store`.
