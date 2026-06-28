# LangSmith SDK / in-app tracing

For applications whose code you control. Adapted from
`deepagentsjs/.agents/skills/langsmith-trace/SKILL.md`.

## LangChain / LangGraph apps (automatic)

Tracing is automatic — set env vars and every chain/graph/LLM step is captured:

```bash
export LANGSMITH_TRACING=true
export LANGSMITH_API_KEY="$(bws secret get <ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGSMITH_PROJECT=my-project          # optional; defaults to "default"
# Route the model through the IntegriBilt gateway:
export OPENAI_API_BASE=http://192.168.254.2:4000
export OPENAI_API_KEY=<gateway virtual key from BWS>
```

Optional:
- `LANGCHAIN_CALLBACKS_BACKGROUND=false` — serverless/short-lived (Python): flush traces before the function
  exits, otherwise the process may die before the background uploader finishes.

> **TODO (fill in):** BWS secret ID for the LangSmith API key.

## Non-LangChain frameworks

- If the framework has **native OpenTelemetry** support, use LangSmith's OpenTelemetry integration.
- If there is **no framework** (or no auto-OTel), use the `traceable` decorator/wrapper and wrap the LLM client.

### Python — `@traceable` + `wrap_openai()`

```python
from langsmith import traceable
from langsmith.wrappers import wrap_openai
from openai import OpenAI

# Wrapped client auto-traces every call; base_url points at the IntegriBilt gateway.
client = wrap_openai(OpenAI(base_url="http://192.168.254.2:4000"))

@traceable
def my_llm_pipeline(question: str) -> str:
    resp = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": question}],
    )
    return resp.choices[0].message.content

# Nested tracing — each @traceable becomes a child span
@traceable
def rag_pipeline(question: str) -> str:
    docs = retrieve_docs(question)
    return generate_answer(question, docs)

@traceable(name="retrieve_docs")
def retrieve_docs(query: str) -> list[str]:
    return docs

@traceable(name="generate_answer")
def generate_answer(question: str, docs: list[str]) -> str:
    return client.chat.completions.create(...)
```

### TypeScript — `traceable()` + `wrapOpenAI()`

```typescript
import { traceable } from "langsmith/traceable";
import { wrapOpenAI } from "langsmith/wrappers";
import OpenAI from "openai";

const client = wrapOpenAI(new OpenAI({ baseURL: "http://192.168.254.2:4000" }));

const myLlmPipeline = traceable(async (question: string): Promise<string> => {
  const resp = await client.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: question }],
  });
  return resp.choices[0].message.content || "";
}, { name: "my_llm_pipeline" });

const retrieveDocs = traceable(async (query: string): Promise<string[]> => {
  return docs;
}, { name: "retrieve_docs" });

const generateAnswer = traceable(async (question: string, docs: string[]): Promise<string> => {
  const resp = await client.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: `${question}\nContext: ${docs.join("\n")}` }],
  });
  return resp.choices[0].message.content || "";
}, { name: "generate_answer" });

const ragPipeline = traceable(async (question: string): Promise<string> => {
  const docs = await retrieveDocs(question);
  return await generateAnswer(question, docs);
}, { name: "rag_pipeline" });
```

## Best practices

- **Apply `traceable` to every nested function** you want visible as a span in LangSmith.
- **Wrapped clients auto-trace all calls** — `wrap_openai()` / `wrapOpenAI()` record every LLM call.
- **Name your traces** for easier filtering (`@traceable(name=...)` / `{ name: ... }`).
- **Add metadata** for searchability (later queryable via `--filter`).
- **Gateway + SDK compose** — point the wrapped client's `base_url`/`baseURL` at `http://192.168.254.2:4000`:
  the gateway callback traces the raw completion while the SDK traces the surrounding structure.
