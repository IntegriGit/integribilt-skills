# Human-in-the-loop — interrupt, resume, approval, validation, idempotency

Built from `langgraph-human-in-the-loop`.

- `interrupt(value)` — pauses execution, surfaces `value` to the caller (under `__interrupt__`).
- `Command(resume=value)` — resumes; the resume value becomes the return of `interrupt()`.
- Requires: a **checkpointer**, a **thread_id**, and a **JSON-serializable** interrupt payload.

**Critical:** on resume the node restarts from the **beginning** — all code before `interrupt()` re-runs.

## Basic interrupt + resume

```python
from langgraph.types import interrupt, Command
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import StateGraph, START, END
from typing_extensions import TypedDict

class State(TypedDict):
    approved: bool

def approval_node(state):
    approved = interrupt("Do you approve this action?")   # pause
    return {"approved": approved}                         # resume lands here

graph = (
    StateGraph(State)
    .add_node("approval", approval_node)
    .add_edge(START, "approval")
    .add_edge("approval", END)
    .compile(checkpointer=InMemorySaver())
)

config = {"configurable": {"thread_id": "thread-1"}}
result = graph.invoke({"approved": False}, config)
print(result["__interrupt__"])                 # [Interrupt(value='Do you approve this action?')]
result = graph.invoke(Command(resume=True), config)
print(result["approved"])                      # True
```

```typescript
import { interrupt, Command, MemorySaver, StateGraph, StateSchema, START, END } from "@langchain/langgraph";
import { z } from "zod";

const State = new StateSchema({ approved: z.boolean().default(false) });

const graph = new StateGraph(State)
  .addNode("approval", async () => ({ approved: interrupt("Do you approve this action?") }))
  .addEdge(START, "approval")
  .addEdge("approval", END)
  .compile({ checkpointer: new MemorySaver() });

const config = { configurable: { thread_id: "thread-1" } };
let result = await graph.invoke({ approved: false }, config);
result = await graph.invoke(new Command({ resume: true }), config);
```

## Approval workflow — interrupt then route

```python
from langgraph.types import interrupt, Command
from langgraph.graph import END
from typing import Literal

def human_review(state) -> Command[Literal["send_reply", "__end__"]]:
    decision = interrupt({
        "email_id": state.get("email_content", ""),
        "draft_response": state.get("draft_response", ""),
        "action": "Please review and approve/edit this response",
    })
    if decision.get("approved"):
        return Command(
            update={"draft_response": decision.get("edited_response", state.get("draft_response", ""))},
            goto="send_reply",
        )
    return Command(update={}, goto=END)
```

## Validation loop — re-prompt until valid

```python
from langgraph.types import interrupt

def get_age_node(state):
    prompt = "What is your age?"
    while True:
        answer = interrupt(prompt)
        if isinstance(answer, int) and answer > 0:
            break
        prompt = f"'{answer}' is not a valid age. Please enter a positive number."
    return {"age": answer}

# each resume supplies the next answer:
graph.invoke(Command(resume="thirty"), config)   # re-interrupts with clearer message
graph.invoke(Command(resume=30), config)          # accepted
```

## Multiple parallel interrupts

When parallel branches each `interrupt()`, resume all at once with a map of interrupt id → value.

```python
def node_a(state):
    return {"vals": [f"a:{interrupt('question_a')}"]}
def node_b(state):
    return {"vals": [f"b:{interrupt('question_b')}"]}

result = graph.invoke({"vals": []}, config)               # both pause
resume_map = {i.id: f"answer for {i.value}" for i in result["__interrupt__"]}
result = graph.invoke(Command(resume=resume_map), config)
# vals = ["a:answer for question_a", "b:answer for question_b"]
```

```typescript
import { isInterrupted, INTERRUPT } from "@langchain/langgraph";

const interrupted = await graph.invoke({ vals: [] }, config);
const resumeMap: Record<string, string> = {};
if (isInterrupted(interrupted)) {
  for (const i of interrupted[INTERRUPT]) {
    if (i.id != null) resumeMap[i.id] = `answer for ${i.value}`;
  }
}
await graph.invoke(new Command({ resume: resumeMap }), config);
```

## Idempotency — side effects before interrupt re-run on resume

In subgraphs, BOTH the parent node and the subgraph node re-execute on resume.

**Do:** upsert (not insert), check-before-create, place side effects after `interrupt()`, or in their own node.
**Don't:** create records or append to lists before `interrupt()` — duplicates on every resume.

```python
# GOOD: upsert is idempotent
def node_a(state):
    db.upsert_user(user_id=state["user_id"], status="pending_approval")
    approved = interrupt("Approve this change?")
    return {"approved": approved}

# GOOD: side effect AFTER interrupt runs once
def node_a(state):
    approved = interrupt("Approve this change?")
    if approved:
        db.create_audit_log(user_id=state["user_id"], action="approved")
    return {"approved": approved}

# BAD: insert duplicates on each resume
def node_a(state):
    db.create_audit_log(user_id=state["user_id"], action="pending_approval")  # re-runs!
    approved = interrupt("Approve this change?")
    return {"approved": approved}
```

## Command(resume) warning

`Command(resume=...)` is the **only** Command pattern valid as input to `invoke`/`stream`. Passing `Command(update=...)` as input resumes from the latest checkpoint and the graph appears stuck — use a plain dict for fresh input, `Command(resume=...)` to resume an interrupt.

## Fixes

```python
# interrupts REQUIRE a checkpointer
graph = builder.compile(checkpointer=InMemorySaver())   # not builder.compile()

# resume with Command, not a plain dict
graph.invoke(Command(resume="approve"), config)         # not {"resume_data": "approve"}
```

### Boundaries — do NOT

- Use interrupts without a checkpointer.
- Resume with a different `thread_id` (creates a new thread).
- Pass `Command(update=...)` as invoke input.
- Run non-idempotent side effects before `interrupt()`.
- Assume code before `interrupt()` runs only once — it re-runs every resume.
