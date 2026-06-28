---
name: langchain
description: >-
  Build production LangChain agents at IntegriBilt — create_agent, @tool/tool(),
  middleware (human-in-the-loop approval, structured output, custom hooks), and
  RAG pipelines (loaders, splitters, embeddings, vector stores). Use when building
  LangChain agents, wiring tools, adding HITL approval gates, getting structured
  Pydantic/Zod output, building retrieval-augmented generation, or choosing
  LangChain vs LangGraph vs Deep Agents. Bakes in the self-hosted LiteLLM Gateway
  (OpenAI-compatible at 192.168.254.2:4000), BWS secret handling, and Langfuse/
  LangSmith tracing. Triggers on: LangChain, create_agent, langchain agent, RAG,
  vector store, embeddings, HumanInTheLoopMiddleware, structured output,
  langchain-core, ChatOpenAI base_url.
---

# LangChain (IntegriBilt edition)

> **Built from** the official LangChain skills, consolidated into one:
> `ecosystem-primer`, `langchain-fundamentals`, `langchain-middleware`,
> `langchain-rag`, and `langchain-dependencies`
> (source: `E:\repos\langchain-skills\config\skills\`). Adapted for the
> IntegriBilt environment (LiteLLM Gateway, BWS secrets, self-hosted observability).

## Overview

LangChain Inc. ships three layered, independently-installed agent tools plus an
observability layer. Pick the **lowest** layer that does the job:

| Layer | Role | Entry point | When |
|-------|------|-------------|------|
| **LangChain** | Agent framework (models, tools, agent loop) | `create_agent(model, tools=[...])` | Single-purpose agent with a fixed tool set; RAG / doc Q&A; a plain model call or chain |
| **LangGraph** | Runtime (durable execution, custom control flow) | `StateGraph(State)` | Deterministic loops, branching, parallel fan-out, precise HITL, state that survives restarts → see sibling **`langgraph`** skill |
| **Deep Agents** | Harness (planning, files, subagents, memory) | `create_deep_agent(model, tools=[...])` | Long sessions needing planning, file management, subagent delegation, persistent memory |
| **LangSmith / Langfuse** | Observability (cross-cutting) | callbacks / env | Always — trace every agent (see Observability) |

**Decision order** (stop at first match): planning/files/subagents/memory → Deep Agents · custom control flow → LangGraph · single agent, fixed tools → LangChain `create_agent` · pure model/retrieval/chain → LangChain direct.

These are **alternatives, not a required stack** — do not pull in LangGraph or Deep Agents unless the decision table sends you there. This skill covers the **LangChain** layer (agents, tools, middleware, RAG). LangGraph graphs live in the sibling `langgraph` skill.

> Docs evolve fast — prefer live docs at **docs.langchain.com** (`/oss/python/...`, `/oss/javascript/...`) over training-data recall. Index: `https://docs.langchain.com/llms.txt`.

## IntegriBilt / LiteLLM integration

All LangChain LLM and embedding calls at IntegriBilt route through the **self-hosted LiteLLM Gateway** — OpenAI-compatible, at `http://192.168.254.2:4000`. Point any `ChatOpenAI` / `OpenAIEmbeddings` at it via `base_url` and a LiteLLM **virtual key**. This gives one place for keys, model routing, cost tracking, and rate limits. Gateway config lives at `/srv/core/litellm/config.yaml` on SVR02. **Use explicit IPs, never `localhost`, for cross-host calls.**

```python
import os
from langchain_openai import ChatOpenAI, OpenAIEmbeddings

# api_key is the LiteLLM VIRTUAL key, fetched from BWS at runtime (see below)
GATEWAY = "http://192.168.254.2:4000"
LITELLM_KEY = os.environ["LITELLM_VIRTUAL_KEY"]

llm = ChatOpenAI(
    base_url=GATEWAY,
    api_key=LITELLM_KEY,
    model="<a-gateway-model>",   # e.g. a model id served by the gateway; run `listmodels` or check config.yaml
    temperature=0,
)

embeddings = OpenAIEmbeddings(
    base_url=GATEWAY,
    api_key=LITELLM_KEY,
    model="<a-gateway-embedding-model>",
)
```

```typescript
import { ChatOpenAI, OpenAIEmbeddings } from "@langchain/openai";

const GATEWAY = "http://192.168.254.2:4000";
const llm = new ChatOpenAI({
  configuration: { baseURL: GATEWAY },
  apiKey: process.env.LITELLM_VIRTUAL_KEY,
  model: "<a-gateway-model>",
  temperature: 0,
});
```

**Why a model instance, not a `"provider:model"` string?** `create_agent("anthropic:claude-...")` talks straight to the provider and **bypasses the gateway** (no cost tracking, needs a raw provider key). At IntegriBilt, **build the `ChatOpenAI` instance pointed at the gateway and pass the instance**:

```python
from langchain.agents import create_agent
agent = create_agent(model=llm, tools=[...])   # llm = gateway-backed ChatOpenAI above
```

> **TODO (fill in):** BWS secret ID for the LiteLLM virtual key (`LITELLM_VIRTUAL_KEY`).
> Use a **non-admin** virtual key for app workloads, not the master key.
> **TODO (fill in as we learn):** canonical list of gateway model ids exposed for LangChain
> (chat + embedding). Some live in `config.yaml`, some are DB-stored (`store_model_in_db`).

### Secrets — always via BWS, never plaintext

Never hardcode keys or write them to disk. Pull at runtime from Bitwarden Secrets Manager:

```bash
export LITELLM_VIRTUAL_KEY="$(bws secret get <SECRET_ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
```

Then read from the environment in code (`os.environ[...]` / `process.env...`). The same rule covers `LANGFUSE_*`, `LANGSMITH_API_KEY`, `TAVILY_API_KEY`, and any vector-store credentials. If a secret ID is unknown, stop and ask — do not invent one.

## Core — create_agent and tools

`create_agent()` is the **only** supported way to build a LangChain agent — it runs the agent loop, tool execution, and state management. Older `AgentExecutor` / `initialize_agent` patterns are outdated; do not use them.

| Parameter | Purpose |
|-----------|---------|
| `model` | Gateway-backed `ChatOpenAI` instance (preferred at IntegriBilt) |
| `tools` | List of `@tool` / `tool()` functions |
| `system_prompt` / `systemPrompt` | Agent instructions |
| `checkpointer` | State persistence (e.g. `MemorySaver()`) — required for memory + HITL |
| `middleware` | Processing hooks (HITL, retry, logging) |
| `response_format` | Pydantic/Zod schema for structured output |

```python
from langchain.agents import create_agent
from langchain_core.tools import tool

@tool
def get_weather(location: str) -> str:
    """Get current weather for a location.

    Use when the user asks about weather. Args:
        location: City name
    """
    return f"Weather in {location}: Sunny, 72F"

agent = create_agent(model=llm, tools=[get_weather], system_prompt="You are a helpful assistant.")
result = agent.invoke({"messages": [{"role": "user", "content": "Weather in Paris?"}]})
print(result["messages"][-1].content)   # access via messages[-1], NOT result.content
```

**Tools** are functions the agent can call — `@tool` decorator (Python) or `tool()` (TypeScript). A clear description with an `Args:` block is load-bearing: it tells the model *when* to call the tool. Vague descriptions ("Does stuff.") cause mis-selection.

**Conversation memory** needs a `checkpointer` + a `thread_id` in config — without both, the agent forgets between invocations:

```python
from langgraph.checkpoint.memory import MemorySaver
agent = create_agent(model=llm, tools=[get_weather], checkpointer=MemorySaver())
cfg = {"configurable": {"thread_id": "user-123"}}
agent.invoke({"messages": [{"role": "user", "content": "My name is Alice"}]}, config=cfg)
agent.invoke({"messages": [{"role": "user", "content": "What's my name?"}]}, config=cfg)  # remembers
```

Full tool patterns, model config, and the complete fix-list → **`references/core-agents.md`**.

## Middleware — HITL, structured output, custom hooks

Middleware intercepts the agent loop. Essential for production: approval gates, retries, guards, logging.

**Human-in-the-Loop (HITL)** — pause before dangerous tools (`send_email`, `delete_*`, anything that posts to Spruce or moves money) for human approval. **Requires a `checkpointer` + `thread_id`.**

```python
from langchain.agents import create_agent
from langchain.agents.middleware import HumanInTheLoopMiddleware
from langgraph.checkpoint.memory import MemorySaver

agent = create_agent(
    model=llm, tools=[send_email, read_email, delete_email],
    checkpointer=MemorySaver(),               # required for HITL
    middleware=[HumanInTheLoopMiddleware(interrupt_on={
        "send_email":   {"allowed_decisions": ["approve", "edit", "reject"]},
        "delete_email": {"allowed_decisions": ["approve", "reject"]},  # no edit
        "read_email":   False,                 # no approval needed
    })],
)
```

Run → detect interrupt → resume with a `Command`:

```python
from langgraph.types import Command
cfg = {"configurable": {"thread_id": "session-1"}}
r1 = agent.invoke({"messages": [{"role": "user", "content": "Email john@x.com"}]}, config=cfg)
if "__interrupt__" in r1:
    ...  # surface to a human
r2 = agent.invoke(Command(resume={"decisions": [{"type": "approve"}]}), config=cfg)
# edit:   {"type": "edit", "edited_action": {"name": "send_email", "args": {...}}}
# reject: {"type": "reject", "feedback": "Needs manager approval"}
```

**Structured output** — typed, validated responses via `response_format` (agent) or `with_structured_output()` (model):

```python
from pydantic import BaseModel, Field
class ContactInfo(BaseModel):
    name: str
    email: str
    phone: str = Field(description="With area code")

agent = create_agent(model=llm, tools=[search], response_format=ContactInfo)
out = agent.invoke({"messages": [{"role": "user", "content": "Find contact for John"}]})
print(out["structured_response"])            # ContactInfo(...)
```

**Custom hooks** — six decorator hooks. Wrap hooks (`wrap_tool_call`, `wrap_model_call`) take `(request, handler)`; before/after hooks (`before_model`, `after_model`, `before_agent`, `after_agent`) take `(state, runtime)`. **Never `yield` inside `@wrap_tool_call`** — it becomes a generator and raises `NotImplementedError`; `return handler(request)` instead.

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
```

Full HITL flows (edit/reject, per-tool policies), all six hooks, and TypeScript equivalents → **`references/middleware.md`**.

## RAG — retrieval-augmented generation

Pipeline: **Index** (Load → Split → Embed → Store) → **Retrieve** (Query → Embed → Search) → **Generate** (Docs + Query → LLM). Embeddings go through the **gateway** (`OpenAIEmbeddings(base_url=...)`).

```python
from langchain_openai import OpenAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_chroma import Chroma

splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
splits = splitter.split_documents(docs)

embeddings = OpenAIEmbeddings(base_url=GATEWAY, api_key=LITELLM_KEY, model="<gateway-embedding-model>")
vectorstore = Chroma.from_documents(splits, embeddings, persist_directory="./chroma_db",
                                    collection_name="my-collection")
retriever = vectorstore.as_retriever(search_kwargs={"k": 4})
```

Wrap retrieval as a tool so an agent can call it:

```python
@tool
def search_docs(query: str) -> str:
    """Search the knowledge base for relevant context."""
    return "\n\n".join(d.page_content for d in retriever.invoke(query))

agent = create_agent(model=llm, tools=[search_docs])
```

**Vector store choice:** InMemory (testing only) · FAISS (local, fast, disk) · Chroma (dev, disk) · Pinecone (managed cloud). Persist anything you don't want to re-index on restart.

**Key rules:** chunk 500–1500 chars with 10–20% overlap · **same embedding model for index and query** (mismatched models = garbage retrieval) · embedding dimensions are fixed per model and can't be mixed in one store · FAISS reload needs `allow_dangerous_deserialization=True`.

Loaders (PDF/web/directory), MMR, metadata filtering, similarity-with-scores, and the full fix-list → **`references/rag.md`**.

## Dependencies / setup

**LangChain 1.0 is the current LTS — start every new project on 1.0+.** 0.3 is maintenance-only; never use it for new work. Packages are independently versioned; install only what you use. Always install `langchain-core` explicitly (it's a peer dep). For the gateway you need `langchain-openai` (the OpenAI-compatible client), regardless of which model the gateway routes to.

```
# requirements.txt — LangChain agent + RAG against the LiteLLM gateway
langchain>=1.0,<2.0
langchain-core>=1.0,<2.0
langchain-openai            # OpenAI-compatible client → points at the gateway
langchain-text-splitters    # semver, keep current
langchain-chroma            # dedicated pkg; prefer over langchain-community
langgraph>=1.0,<2.0         # only if you use checkpointers / HITL / graphs
langfuse                    # observability (see below); or: langsmith>=0.3.0
```

- **Python 3.10+** / **Node 20+** minimum.
- Prefer **dedicated integration packages** (`langchain-chroma`, `langchain-tavily`, `langchain-pinecone`) over `langchain-community`. `langchain-community` is **NOT semver** — pin it to an exact minor series (`>=0.4.0,<0.5.0`).
- TypeScript monorepos: list `@langchain/core` explicitly — it won't always hoist.

Full package tables, project templates, and versioning policy → **`references/dependencies.md`**.

## Observability

Trace **every** agent — it's how we debug tool loops and watch cost. Two backends; both attach via LangChain callbacks. Cross-link the sibling **`langfuse`** and **`langsmith`** skills for backend setup.

**Langfuse** (self-hosted, preferred for IntegriBilt — keeps trace data in-house):

```python
from langfuse.langchain import CallbackHandler
handler = CallbackHandler()   # reads LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY / LANGFUSE_HOST from env
agent.invoke({"messages": [{"role": "user", "content": "..."}]}, config={"callbacks": [handler]})
```

**LangSmith** (env-driven, no code change — set vars and traces flow):

```bash
export LANGSMITH_TRACING=true
export LANGSMITH_API_KEY="$(bws secret get <SECRET_ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGSMITH_PROJECT="<project-name>"
```

Because the gateway is OpenAI-compatible, LiteLLM **also** records its own request/cost logs — LangChain tracing and gateway logs are complementary, not redundant.

> **TODO (fill in):** BWS secret IDs for `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`,
> and `LANGSMITH_API_KEY`; self-hosted `LANGFUSE_HOST` URL on the IntegriBilt network.

## Anti-patterns

- **Hardcoding keys / pointing at a provider directly.** Always go through the gateway (`base_url`) with a BWS-sourced virtual key. Passing `"anthropic:..."` to `create_agent` bypasses the gateway.
- **Using `localhost` for the gateway** in cross-host code — use `192.168.254.2:4000`.
- **`result.content`** — the result is a dict; read `result["messages"][-1].content`.
- **HITL without a `checkpointer` + `thread_id`** — the interrupt can't persist; it silently won't work.
- **`yield` inside `@wrap_tool_call`** — raises `NotImplementedError`. Return the handler result.
- **No `recursion_limit`** — runaway loops. Set `config={"recursion_limit": 10}`.
- **InMemory vector store in production** — lost on restart. Persist (Chroma/FAISS/Pinecone).
- **Different embedding models for index vs query** — silent retrieval garbage. Use one model both sides.
- **Vague tool descriptions** — the model can't tell when to call them.
- **Starting on LangChain 0.3** or leaving `langchain-community` unpinned.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `401 / invalid api key` from gateway | Bad/empty virtual key, or hit the provider directly | Confirm `LITELLM_VIRTUAL_KEY` is BWS-sourced and non-empty; `base_url` set to `192.168.254.2:4000` |
| `Connection refused` to `:4000` | Gateway down, or used `localhost` cross-host | Use explicit IP; check the LiteLLM container on SVR02 (see infra skill) |
| `model not found` | Model id not served by the gateway | List gateway models / check `/srv/core/litellm/config.yaml`; some are DB-stored |
| Agent forgets context | No `checkpointer`/`thread_id` | Add `MemorySaver()` + `config={"configurable": {"thread_id": ...}}` |
| HITL never interrupts | Missing `checkpointer` or `thread_id` | Both are required for HITL |
| `NotImplementedError` in middleware | `yield` in `@wrap_tool_call` | `return handler(request)` |
| `AttributeError` on result | `result.content` | `result["messages"][-1].content` |
| Empty / wrong RAG hits | Embedding model mismatch, or chunks too small/large | Same model index+query; chunk 500–1500, 10–20% overlap |
| FAISS load error | Deserialization blocked | `allow_dangerous_deserialization=True` |
| Agent loops forever | No iteration cap | `config={"recursion_limit": 10}` |
| No traces in Langfuse/LangSmith | Callback/env not wired | Pass the `CallbackHandler`, or set `LANGSMITH_TRACING=true` + key |

## References

- **`references/core-agents.md`** — `create_agent`, tools, persistence, model config, common fixes (Py + TS). *Built from `langchain-fundamentals`.*
- **`references/middleware.md`** — HITL (approve/edit/reject, per-tool policies), structured output, six custom hooks (Py + TS). *Built from `langchain-middleware`.*
- **`references/rag.md`** — loaders, splitters, embeddings, vector stores, retrieval (MMR, metadata, scores), fixes (Py + TS). *Built from `langchain-rag`.*
- **`references/dependencies.md`** — package tables, env requirements, project templates, versioning policy. *Built from `langchain-dependencies`.*
- **`references/ecosystem.md`** — LangChain vs LangGraph vs Deep Agents, mixing layers, docs map. *Built from `ecosystem-primer`.*

Sibling skills: **`langgraph`** (custom graphs/runtime), **`langfuse`** / **`langsmith`** (observability backends), **`integribilt-infrastructure`** (gateway/SVR02 ops, BWS).
