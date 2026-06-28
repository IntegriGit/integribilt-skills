# Tracing & the Langfuse SDK

Use the SDK when you want spans **inside** application code (retrieval steps, tool
calls, sub-functions), beyond the gateway-level traces the LiteLLM callback
already produces. If the gateway callback is on, you usually do not also need SDK
tracing for the LLM call itself — pick one layer to avoid double-logging.

Concepts:
- **Trace** — one logical request (a user turn, a job).
- **Generation** — an LLM call (model, params, input, output, token usage, cost).
- **Span** — any other unit of work (retrieval, parsing, a tool).
- **Score** — a numeric/boolean quality or feedback signal on a trace or observation.

Keys come from env (`LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_HOST`),
sourced from BWS. Never pass literals.

---

## Basic tracing

```python
from langfuse import Langfuse

langfuse = Langfuse()  # reads keys + host from env

trace = langfuse.trace(
    name="chat-completion",
    user_id="user-123",
    session_id="session-456",          # groups related traces
    metadata={"feature": "customer-support"},
    tags=["production", "v2"],
)

generation = trace.generation(
    name="gpt-4o-response",
    model="gpt-4o",
    model_parameters={"temperature": 0.7},
    input={"messages": [{"role": "user", "content": "Hello"}]},
    metadata={"attempt": 1},
)

# ... make the real LLM call (e.g. via the gateway) ...

generation.end(
    output=response_text,
    usage={"input": prompt_tokens, "output": completion_tokens},
)

trace.score(name="user-feedback", value=1, comment="User clicked helpful")

langfuse.flush()   # REQUIRED before exit in serverless / short-lived processes
```

---

## OpenAI drop-in (auto-tracing)

Swap the import; every call is traced automatically. Langfuse-specific kwargs
(`name`, `session_id`, `user_id`, `tags`, `metadata`) ride along.

```python
from langfuse.openai import openai

response = openai.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello"}],
    name="greeting",
    session_id="session-123",
    user_id="user-456",
    tags=["test"],
    metadata={"feature": "chat"},
)
```

> To route this through the IntegriBilt gateway, point the OpenAI client's
> `base_url` at `http://192.168.254.2:4000` and use a LiteLLM virtual key (from
> BWS). You can run the gateway callback AND the SDK drop-in, but that
> double-logs — prefer one.

### Streaming

```python
stream = openai.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Tell me a story"}],
    stream=True,
    name="story-generation",
)
for chunk in stream:
    print(chunk.choices[0].delta.content, end="")
```

### Async

```python
from langfuse.openai import AsyncOpenAI

async_client = AsyncOpenAI()

async def main():
    response = await async_client.chat.completions.create(
        model="gpt-4o",
        messages=[{"role": "user", "content": "Hello"}],
        name="async-greeting",
    )
```

---

## Decorator pattern (cleanest for function-based apps)

`@observe()` makes a trace at the entry point and spans for nested calls;
`as_type="generation"` marks an LLM call. Mutate the active trace with
`langfuse_context`.

```python
from langfuse.decorators import observe, langfuse_context

@observe()                          # top-level => trace
def chat_handler(user_id: str, message: str) -> str:
    context = get_context(message)  # nested @observe => span
    return generate_response(message, context)

@observe()                          # span
def get_context(message: str) -> str:
    docs = retriever.get_relevant_documents(message)
    return "\n".join(d.page_content for d in docs)

@observe(as_type="generation")      # generation span
def generate_response(message: str, context: str) -> str:
    response = openai.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": f"Context: {context}"},
            {"role": "user", "content": message},
        ],
    )
    return response.choices[0].message.content

@observe()
def main_flow(user_input: str):
    langfuse_context.update_current_trace(
        user_id="user-123", session_id="session-456", tags=["production"]
    )
    result = process(user_input)
    langfuse_context.score_current_trace(name="success", value=1 if result else 0)
    return result

@observe()                          # works with async too
async def async_handler(message: str):
    return await async_generate(message)
```

---

## Flushing — the #1 lost-trace cause

Traces are **batched**. Short-lived processes (serverless, CLI jobs, scripts) can
exit before the batch ships. Always `langfuse.flush()` before exit, or use a
context manager where available. For critical single traces consider a synchronous
send. (See `troubleshooting.md`.)

---

Source: consolidated from `awesome-skills/langfuse` and `c-skills/langfuse`
(vibeship-spawner-skills, Apache 2.0).
