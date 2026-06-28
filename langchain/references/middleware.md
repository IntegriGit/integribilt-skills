# Middleware — HITL, structured output, custom hooks

> Built from the official `langchain-middleware` skill. **Every HITL workflow
> requires a `checkpointer` + a `thread_id` in config.** At IntegriBilt, gate any
> tool that posts to Spruce, moves money, sends mail, or deletes data behind HITL.

## Human-in-the-Loop

### Setup
```python
from langchain.agents import create_agent
from langchain.agents.middleware import HumanInTheLoopMiddleware
from langgraph.checkpoint.memory import MemorySaver
from langchain.tools import tool

@tool
def send_email(to: str, subject: str, body: str) -> str:
    """Send an email."""
    return f"Email sent to {to}"

agent = create_agent(
    model=llm,
    tools=[send_email],
    checkpointer=MemorySaver(),            # REQUIRED for HITL
    middleware=[HumanInTheLoopMiddleware(interrupt_on={
        "send_email": {"allowed_decisions": ["approve", "edit", "reject"]},
    })],
)
```
```typescript
import { createAgent, humanInTheLoopMiddleware } from "langchain";
import { MemorySaver } from "@langchain/langgraph";

const agent = createAgent({
  model: llm,
  tools: [sendEmail],
  checkpointer: new MemorySaver(),
  middleware: [humanInTheLoopMiddleware({
    interruptOn: { send_email: { allowedDecisions: ["approve", "edit", "reject"] } },
  })],
});
```

### Run, detect interrupt, resume
```python
from langgraph.types import Command
config = {"configurable": {"thread_id": "session-1"}}

result1 = agent.invoke(
    {"messages": [{"role": "user", "content": "Send email to john@example.com"}]}, config=config)
if "__interrupt__" in result1:
    print(f"Waiting for approval: {result1['__interrupt__']}")

result2 = agent.invoke(Command(resume={"decisions": [{"type": "approve"}]}), config=config)
```
```typescript
import { Command } from "@langchain/langgraph";
const config = { configurable: { thread_id: "session-1" } };
const result1 = await agent.invoke({ messages: [{ role: "user", content: "Send email to john@example.com" }] }, config);
if (result1.__interrupt__) console.log(`Waiting: ${result1.__interrupt__}`);
const result2 = await agent.invoke(new Command({ resume: { decisions: [{ type: "approve" }] } }), config);
```

### Edit tool arguments before approving
```python
result2 = agent.invoke(Command(resume={"decisions": [{
    "type": "edit",
    "edited_action": {"name": "send_email",
        "args": {"to": "alice@company.com", "subject": "Updated", "body": "..."}},
}]}), config=config)
```
```typescript
const result2 = await agent.invoke(new Command({ resume: { decisions: [{
  type: "edit",
  editedAction: { name: "send_email", args: { to: "alice@company.com", subject: "Updated", body: "..." } },
}] } }), config);
```

### Reject with feedback
```python
result2 = agent.invoke(Command(resume={"decisions": [{
    "type": "reject",
    "feedback": "Cannot delete customer data without manager approval",
}]}), config=config)
```

### Per-tool policies (risk-tiered)
```python
agent = create_agent(
    model=llm, tools=[send_email, read_email, delete_email], checkpointer=MemorySaver(),
    middleware=[HumanInTheLoopMiddleware(interrupt_on={
        "send_email":   {"allowed_decisions": ["approve", "edit", "reject"]},
        "delete_email": {"allowed_decisions": ["approve", "reject"]},   # no edit
        "read_email":   False,                                          # no HITL
    })],
)
```

## Structured output

Typed, validated responses via `response_format` (agent) or `with_structured_output()` (model). At IntegriBilt the model is the gateway-backed `ChatOpenAI`.

### Python
```python
from pydantic import BaseModel, Field

class ContactInfo(BaseModel):
    name: str
    email: str
    phone: str = Field(description="Phone number with area code")

# Agent-level
agent = create_agent(model=llm, tools=[search], response_format=ContactInfo)
result = agent.invoke({"messages": [{"role": "user", "content": "Find contact for John"}]})
print(result["structured_response"])

# Model-level (no agent)
structured = llm.with_structured_output(ContactInfo)
print(structured.invoke("Extract: John, john@example.com, 555-1234"))
```
### TypeScript
```typescript
import { z } from "zod";
const ContactInfo = z.object({
  name: z.string(),
  email: z.string().email(),
  phone: z.string().describe("Phone number with area code"),
});
const structured = llm.withStructuredOutput(ContactInfo);
const response = await structured.invoke("Extract: John, john@example.com, 555-1234");
```

## Custom middleware hooks

Six decorator hooks, two signatures:
- **Wrap hooks** (`wrap_tool_call`, `wrap_model_call`): `(request, handler)` — call `handler(request)` to proceed, or return early to short-circuit.
- **Before/after hooks** (`before_model`, `after_model`, `before_agent`, `after_agent`): `(state, runtime)` — inspect/modify state; return `None` or a dict of updates.

### wrap_tool_call — retry + guard
**Do NOT `yield`** — that makes a generator and raises `NotImplementedError`.
```python
from langchain.agents.middleware import wrap_tool_call

@wrap_tool_call
def retry_middleware(request, handler):
    for attempt in range(3):
        try:
            return handler(request)
        except Exception:
            if attempt == 2:
                raise

@wrap_tool_call
def guard_middleware(request, handler):
    if request.tool_call["name"] == "dangerous_tool":
        return "This tool is disabled"     # short-circuit
    return handler(request)
```
```typescript
import { createMiddleware } from "langchain";
const retryMiddleware = createMiddleware({
  wrapToolCall: async (request, handler) => {
    for (let attempt = 0; attempt < 3; attempt++) {
      try { return await handler(request); }
      catch (e) { if (attempt === 2) throw e; }
    }
  },
});
```

### before/after hooks — logging
```python
from langchain.agents.middleware import before_model, after_model

@before_model
def log_calls(state, runtime):
    print(f"Calling model with {len(state['messages'])} messages")

@after_model
def check_output(state, runtime):
    print("Model responded")
```
```typescript
import { createMiddleware } from "langchain";
const loggingMiddleware = createMiddleware({
  beforeModel: (state, runtime) => console.log(`Calling model with ${state.messages.length} messages`),
  afterModel: (state, runtime) => console.log("Model responded"),
});
```

## Boundaries
**Can configure:** which tools need approval, allowed decisions per tool, the six hooks, tool-specific middleware.
**Cannot:** interrupt *after* tool execution (must be before); skip the checkpointer requirement for HITL.

## Common fixes
```python
# Missing checkpointer — HITL silently won't persist
# WRONG
agent = create_agent(model=llm, tools=[send_email], middleware=[HumanInTheLoopMiddleware({...})])
# CORRECT
agent = create_agent(model=llm, tools=[send_email], checkpointer=MemorySaver(),
                     middleware=[HumanInTheLoopMiddleware({...})])

# No thread_id
# WRONG: agent.invoke(input)
# CORRECT: agent.invoke(input, config={"configurable": {"thread_id": "user-123"}})

# Wrong resume syntax
# WRONG: agent.invoke({"resume": {"decisions": [...]}})
# CORRECT:
from langgraph.types import Command
agent.invoke(Command(resume={"decisions": [{"type": "approve"}]}), config=config)
```
