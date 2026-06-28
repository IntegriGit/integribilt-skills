# Core — create_agent & tools

> Built from the official `langchain-fundamentals` skill, adapted for IntegriBilt
> (gateway-backed models). At IntegriBilt pass a `ChatOpenAI` instance pointed at
> the LiteLLM Gateway (`base_url="http://192.168.254.2:4000"`) as `model=` — do not
> pass a `"provider:model"` string (that bypasses the gateway). See SKILL.md for setup.

## create_agent configuration

| Parameter | Purpose | Example |
|-----------|---------|---------|
| `model` | LLM to use | gateway `ChatOpenAI` instance (preferred) or `"anthropic:claude-sonnet-4-5"` (bypasses gateway) |
| `tools` | List of tools | `[search, calculator]` |
| `system_prompt` / `systemPrompt` | Agent instructions | `"You are a helpful assistant"` |
| `checkpointer` | State persistence | `MemorySaver()` |
| `middleware` | Processing hooks | `[HumanInTheLoopMiddleware(...)]` |
| `response_format` | Structured output schema | `ContactInfo` (Pydantic) / Zod object |

## Basic agent

### Python
```python
from langchain.agents import create_agent
from langchain_core.tools import tool

@tool
def get_weather(location: str) -> str:
    """Get current weather for a location.

    Args:
        location: City name
    """
    return f"Weather in {location}: Sunny, 72F"

agent = create_agent(
    model=llm,                       # gateway-backed ChatOpenAI (see SKILL.md)
    tools=[get_weather],
    system_prompt="You are a helpful assistant.",
)

result = agent.invoke({"messages": [{"role": "user", "content": "What's the weather in Paris?"}]})
print(result["messages"][-1].content)
```

### TypeScript
```typescript
import { createAgent } from "langchain";
import { tool } from "@langchain/core/tools";
import { z } from "zod";

const getWeather = tool(
  async ({ location }) => `Weather in ${location}: Sunny, 72F`,
  {
    name: "get_weather",
    description: "Get current weather for a location.",
    schema: z.object({ location: z.string().describe("City name") }),
  }
);

const agent = createAgent({
  model: llm,                        // gateway-backed ChatOpenAI
  tools: [getWeather],
  systemPrompt: "You are a helpful assistant.",
});

const result = await agent.invoke({
  messages: [{ role: "user", content: "What's the weather in Paris?" }],
});
console.log(result.messages[result.messages.length - 1].content);
```

## Persistence (conversation memory)

A `checkpointer` + a `thread_id` in config make the agent remember across invocations.

### Python
```python
from langgraph.checkpoint.memory import MemorySaver

agent = create_agent(model=llm, tools=[search], checkpointer=MemorySaver())
config = {"configurable": {"thread_id": "user-123"}}
agent.invoke({"messages": [{"role": "user", "content": "My name is Alice"}]}, config=config)
result = agent.invoke({"messages": [{"role": "user", "content": "What's my name?"}]}, config=config)
# "Your name is Alice"
```

### TypeScript
```typescript
import { MemorySaver } from "@langchain/langgraph";

const agent = createAgent({ model: llm, tools: [search], checkpointer: new MemorySaver() });
const config = { configurable: { thread_id: "user-123" } };
await agent.invoke({ messages: [{ role: "user", content: "My name is Alice" }] }, config);
const result = await agent.invoke({ messages: [{ role: "user", content: "What's my name?" }] }, config);
```

## Defining tools

Tools are functions agents can call. A clear description + `Args:` block tells the model *when* to call it.

### Python
```python
from langchain_core.tools import tool

@tool
def add(a: float, b: float) -> float:
    """Add two numbers.

    Args:
        a: First number
        b: Second number
    """
    return a + b
```

### TypeScript
```typescript
import { tool } from "@langchain/core/tools";
import { z } from "zod";

const add = tool(
  async ({ a, b }) => a + b,
  {
    name: "add",
    description: "Add two numbers.",
    schema: z.object({
      a: z.number().describe("First number"),
      b: z.number().describe("Second number"),
    }),
  }
);
```

## Model configuration

At IntegriBilt, build a gateway-backed instance and pass it:

```python
from langchain_openai import ChatOpenAI
llm = ChatOpenAI(base_url="http://192.168.254.2:4000",
                 api_key=LITELLM_KEY, model="<gateway-model>", temperature=0)
agent = create_agent(model=llm, tools=[...])
```

`create_agent` *also* accepts provider strings (`"openai:gpt-4.1"`, `"anthropic:claude-sonnet-4-5"`) and provider instances (`ChatAnthropic(...)`), but those talk to the provider directly and **skip the gateway** — avoid them in IntegriBilt workloads.

## Common fixes

### Missing tool description
```python
# WRONG: vague — model can't tell when to use it
@tool
def bad_tool(input: str) -> str:
    """Does stuff."""
    return "result"

# CORRECT: clear, specific, with Args
@tool
def search(query: str) -> str:
    """Search the web for current information about a topic.

    Use this when you need recent data or facts. Args:
        query: The search query (2-10 words recommended)
    """
    return web_search(query)
```

### No checkpointer (agent forgets)
```python
# WRONG
agent = create_agent(model=llm, tools=[search])
# CORRECT
from langgraph.checkpoint.memory import MemorySaver
agent = create_agent(model=llm, tools=[search], checkpointer=MemorySaver())
agent.invoke(input, config={"configurable": {"thread_id": "session-1"}})
```

### Infinite loop
```python
# WRONG: could loop forever
result = agent.invoke({"messages": [("user", "Do research")]})
# CORRECT: cap iterations
result = agent.invoke({"messages": [("user", "Do research")]}, config={"recursion_limit": 10})
```
```typescript
const result = await agent.invoke({ messages: [["user", "Do research"]] }, { recursionLimit: 10 });
```

### Accessing the result wrong
```python
# WRONG: AttributeError
result = agent.invoke({"messages": [{"role": "user", "content": "Hello"}]})
print(result.content)
# CORRECT
print(result["messages"][-1].content)
```
```typescript
// WRONG: undefined
console.log(result.content);
// CORRECT
console.log(result.messages[result.messages.length - 1].content);
```
