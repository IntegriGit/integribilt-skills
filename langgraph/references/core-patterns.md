# Core patterns — StateGraph, nodes, edges, Command, Send, streaming

Built from `langgraph-fundamentals`. Python and TypeScript variants for each pattern.

## State with reducers

```python
from typing_extensions import TypedDict, Annotated
import operator

class State(TypedDict):
    name: str                                  # default: overwrites
    messages: Annotated[list, operator.add]    # appends to list
    total: Annotated[int, operator.add]        # sums integers
```

```typescript
import { StateSchema, ReducedValue, MessagesValue } from "@langchain/langgraph";
import { z } from "zod";

const State = new StateSchema({
  name: z.string(),            // overwrites
  messages: MessagesValue,     // built-in for messages
  items: new ReducedValue(
    z.array(z.string()).default(() => []),
    { reducer: (current, update) => current.concat(update) }
  ),
});
```

### Wrong vs right

```python
# WRONG: list overwritten, "A" lost
class State(TypedDict):
    messages: list
# CORRECT
class State(TypedDict):
    messages: Annotated[list, operator.add]

# WRONG: mutate + return full state
def my_node(state: State) -> State:
    state["field"] = "updated"
    return state
# CORRECT: return only the updates
def my_node(state: State) -> dict:
    return {"field": "updated"}
```

## Node signatures

| Python | When |
|--------|------|
| `def node(state)` | state only |
| `def node(state, config: RunnableConfig)` | thread_id, tags, configurable |
| `def node(state, runtime: Runtime[Context])` | runtime context, store, stream writer |

```python
from langchain_core.runnables import RunnableConfig
from langgraph.runtime import Runtime

def node_with_config(state, config: RunnableConfig):
    thread_id = config["configurable"]["thread_id"]
    return {"results": f"Thread: {thread_id}"}

def node_with_runtime(state, runtime: Runtime[Context]):
    return {"results": f"User: {runtime.context.user_id}"}
```

```typescript
import { GraphNode } from "@langchain/langgraph";

const nodeWithConfig: GraphNode<typeof State> = (state, config) => {
  const threadId = config?.configurable?.thread_id;
  return { results: `Thread: ${threadId}` };
};
```

## Basic graph

```python
from langgraph.graph import StateGraph, START, END
from typing_extensions import TypedDict

class State(TypedDict):
    input: str
    output: str

def process_input(state): return {"output": f"Processed: {state['input']}"}
def finalize(state):      return {"output": state["output"].upper()}

graph = (
    StateGraph(State)
    .add_node("process", process_input)
    .add_node("finalize", finalize)
    .add_edge(START, "process")
    .add_edge("process", "finalize")
    .add_edge("finalize", END)
    .compile()
)
print(graph.invoke({"input": "hello"})["output"])  # PROCESSED: HELLO
```

```typescript
import { StateGraph, StateSchema, START, END } from "@langchain/langgraph";
import { z } from "zod";

const State = new StateSchema({ input: z.string(), output: z.string().default("") });

const graph = new StateGraph(State)
  .addNode("process", async (s) => ({ output: `Processed: ${s.input}` }))
  .addNode("finalize", async (s) => ({ output: s.output.toUpperCase() }))
  .addEdge(START, "process")
  .addEdge("process", "finalize")
  .addEdge("finalize", END)
  .compile();

console.log((await graph.invoke({ input: "hello" })).output);  // PROCESSED: HELLO
```

## Conditional edges

```python
from typing import Literal
from langgraph.graph import StateGraph, START, END

def classify(state):
    return {"route": "weather" if "weather" in state["query"].lower() else "general"}

def route_query(state) -> Literal["weather", "general"]:
    return state["route"]

graph = (
    StateGraph(State)
    .add_node("classify", classify)
    .add_node("weather", lambda s: {"result": "Sunny, 72F"})
    .add_node("general", lambda s: {"result": "General response"})
    .add_edge(START, "classify")
    .add_conditional_edges("classify", route_query, ["weather", "general"])
    .add_edge("weather", END)
    .add_edge("general", END)
    .compile()
)
```

```typescript
const graph = new StateGraph(State)
  .addNode("classify", async (s) =>
    ({ route: s.query.toLowerCase().includes("weather") ? "weather" : "general" }))
  .addNode("weather", async () => ({ result: "Sunny, 72F" }))
  .addNode("general", async () => ({ result: "General response" }))
  .addEdge(START, "classify")
  .addConditionalEdges("classify", (s) => s.route, ["weather", "general"])
  .addEdge("weather", END)
  .addEdge("general", END)
  .compile();
```

## Command — update state AND route

Fields: `update` (state delta), `goto` (next node[s]), `resume` (HITL — see human-in-the-loop).

```python
from langgraph.types import Command
from typing import Literal

def node_a(state) -> Command[Literal["node_b", "node_c"]]:
    new_count = state["count"] + 1
    if new_count > 5:
        return Command(update={"count": new_count}, goto="node_c")
    return Command(update={"count": new_count}, goto="node_b")
```

```typescript
import { Command } from "@langchain/langgraph";

const nodeA = async (state) => {
  const newCount = state.count + 1;
  return newCount > 5
    ? new Command({ update: { count: newCount }, goto: "node_c" })
    : new Command({ update: { count: newCount }, goto: "node_b" });
};
// declare destinations in TS:
builder.addNode("node_a", nodeA, { ends: ["node_b", "node_c"] });
```

- **Python**: annotate return as `Command[Literal["node_b", "node_c"]]`.
- **TS**: pass `{ ends: [...] }` as the third `addNode` arg.
- **Warning**: `Command` adds *dynamic* edges; static `add_edge` edges still execute. Both fire if both exist.

## Send API — fan-out to parallel workers

```python
from langgraph.types import Send
from typing import Annotated
import operator

class OrchestratorState(TypedDict):
    tasks: list[str]
    results: Annotated[list, operator.add]   # reducer REQUIRED
    summary: str

def orchestrator(state):
    return [Send("worker", {"task": t}) for t in state["tasks"]]

def worker(state):     return {"results": [f"Completed: {state['task']}"]}
def synthesize(state): return {"summary": f"Processed {len(state['results'])} tasks"}

graph = (
    StateGraph(OrchestratorState)
    .add_node("worker", worker)
    .add_node("synthesize", synthesize)
    .add_conditional_edges(START, orchestrator, ["worker"])
    .add_edge("worker", "synthesize")
    .add_edge("synthesize", END)
    .compile()
)
```

```typescript
import { Send, StateGraph, StateSchema, ReducedValue, START, END } from "@langchain/langgraph";
import { z } from "zod";

const State = new StateSchema({
  tasks: z.array(z.string()),
  results: new ReducedValue(z.array(z.string()).default(() => []),
    { reducer: (c, u) => c.concat(u) }),
  summary: z.string().default(""),
});

const graph = new StateGraph(State)
  .addNode("worker", async (s: { task: string }) => ({ results: [`Completed: ${s.task}`] }))
  .addNode("synthesize", async (s) => ({ summary: `Processed ${s.results.length} tasks` }))
  .addConditionalEdges(START, (s) => s.tasks.map((task) => new Send("worker", { task })), ["worker"])
  .addEdge("worker", "synthesize")
  .addEdge("synthesize", END)
  .compile();
```

Without the reducer on `results`, the last worker overwrites the rest.

## Invoke & stream

```python
result = graph.invoke({"input": "hello"})
result = graph.invoke({"input": "hello"}, {"configurable": {"thread_id": "1"}})
```

| Mode | Streams | Use |
|------|---------|-----|
| `values` | full state per step | monitoring |
| `updates` | deltas | incremental |
| `messages` | LLM tokens + metadata | chat UIs |
| `custom` | user data | progress |

```python
for token, meta in graph.stream({"messages": [...]}, stream_mode="messages"):
    if hasattr(token, "content"):
        print(token.content, end="", flush=True)

# custom progress from inside a node
from langgraph.config import get_stream_writer
def my_node(state):
    writer = get_stream_writer()
    writer("Processing step 1...")
    return {"result": "done"}
```

```typescript
for await (const [token] of graph.stream({ messages: [...] }, { streamMode: "messages" })) {
  if (token.content) process.stdout.write(token.content);
}
```

## Error handling (4-tier)

| Error | Owner | Strategy |
|-------|-------|----------|
| Transient | system | `RetryPolicy(max_attempts=3)` on node |
| LLM-recoverable | LLM | `ToolNode(tools, handle_tool_errors=True)` |
| User-fixable | human | `interrupt({...})` |
| Unexpected | dev | let bubble up |

```python
from langgraph.types import RetryPolicy
from langgraph.prebuilt import ToolNode

workflow.add_node("search", search_fn,
                  retry_policy=RetryPolicy(max_attempts=3, initial_interval=1.0))
workflow.add_node("tools", ToolNode(tools, handle_tool_errors=True))
```

```typescript
import { ToolNode } from "@langchain/langgraph/prebuilt";

workflow.addNode("search", searchFn, { retryPolicy: { maxAttempts: 3, initialInterval: 1.0 } });
workflow.addNode("tools", new ToolNode(tools, { handleToolErrors: true }));
```

## Common fixes

```python
# compile before execution
graph = builder.compile()

# break infinite loops with a conditional path to END
def should_continue(state):
    return END if state["count"] > 10 else "node_b"
builder.add_conditional_edges("node_a", should_continue)

# add nodes BEFORE referencing in edges; routers must return existing node names
# START is entry-only — never add_edge("node", START)
# reducer types must match (list reducer needs a list update)
```

### Boundaries — do NOT

- Mutate state directly — return partial-update dicts.
- Route back to `START`.
- Forget reducers on list fields.
- Mix static edges with `Command(goto)` without expecting both to run.
