# Dependencies & setup

> Built from the official `langchain-dependencies` skill. **LangChain 1.0 is the
> current LTS — start every new project on 1.0+.** 0.3 is maintenance-only. At
> IntegriBilt you always need `langchain-openai` (the OpenAI-compatible client)
> because all model/embedding traffic goes through the LiteLLM Gateway, regardless
> of which underlying provider the gateway routes to.

## Environment requirements

| Requirement | Python | TypeScript / Node |
|-------------|--------|-------------------|
| Runtime minimum | **Python 3.10+** | **Node.js 20+** |
| LangChain | **1.0+ (LTS)** | **1.0+ (LTS)** |
| LangSmith SDK | >= 0.3.0 | >= 0.3.0 |

## Framework choice (pick one orchestration layer)

| Framework | When | Core package |
|-----------|------|--------------|
| **LangChain** (`create_agent`) | Single agent, fixed tools; RAG; plain model call | `langchain` + `langchain-core` |
| **LangGraph** | Custom control flow, loops, branching, durable state | `langgraph` / `@langchain/langgraph` |
| **Deep Agents** | Planning, files, subagents, memory out of the box | `deepagents` (bundles LangGraph) |

All sit on `langchain` + `langchain-core` (+ observability).

## Core packages — Python

Always required: `langchain` (1.0), `langchain-core` (1.0, peer dep — install explicitly), plus observability (`langfuse` or `langsmith>=0.3.0`).

Orchestration (pick one): `langgraph` (1.0) **or** `deepagents` (latest).

Model providers: at IntegriBilt use **`langchain-openai`** pointed at the gateway. (The full provider list — `langchain-anthropic`, `langchain-google-genai`, `langchain-mistralai`, `langchain-groq`, `langchain-cohere`, `langchain-ollama`, `langchain-aws`, etc. — applies only if you bypass the gateway, which IntegriBilt workloads should not do.)

Tools / retrieval: `langchain-tavily` (web search, prefer latest), `langchain-text-splitters` (semver), `langchain-chroma` / `langchain-pinecone` / `langchain-qdrant` / `langchain-weaviate` (dedicated, prefer latest), `faiss-cpu` (via community). **`langchain-community` is NOT semver — pin to an exact minor series.**

## Core packages — TypeScript

Always required: `@langchain/core` (1.0, peer dep — list explicitly in monorepos), `langchain` (1.0), observability.
Orchestration: `@langchain/langgraph` (1.0) or `deepagents`.
Gateway client: `@langchain/openai`.
Tools/retrieval: `@langchain/tavily`, `@langchain/pinecone`, `@langchain/qdrant`, `@langchain/weaviate`; `@langchain/community` sparingly.

## Project templates

### LangChain agent + RAG against the gateway (Python)
```
# requirements.txt
langchain>=1.0,<2.0
langchain-core>=1.0,<2.0
langchain-openai            # OpenAI-compatible client → LiteLLM gateway
langchain-text-splitters
langchain-chroma
langgraph>=1.0,<2.0         # only if checkpointers / HITL / graphs
langfuse                    # or: langsmith>=0.3.0
# optional web search:
# langchain-tavily
```

### LangGraph project (TypeScript)
```json
{
  "dependencies": {
    "@langchain/core": "^1.0.0",
    "langchain": "^1.0.0",
    "@langchain/openai": "^1.0.0",
    "@langchain/langgraph": "^1.0.0",
    "langsmith": "^0.3.0"
  }
}
```

### Deep Agents (Python)
```
deepagents            # bundles langgraph internally
langchain>=1.0,<2.0
langchain-core>=1.0,<2.0
langchain-openai
langfuse              # or langsmith>=0.3.0
```

## Versioning policy

| Package group | Versioning | Strategy |
|---------------|------------|----------|
| `langchain`, `langchain-core` | semver (1.0 LTS) | `>=1.0,<2.0` |
| `langgraph` | semver (v1 LTS) | `>=1.0,<2.0` |
| `langsmith` | semver | `>=0.3.0` |
| Dedicated integrations (`langchain-tavily`, `langchain-chroma`, …) | independent | latest within major |
| `langchain-community` | **NOT semver** | pin exact minor `>=0.4.0,<0.5.0` |
| `deepagents` | project releases | pin tested version in prod |

Breaking changes only in major bumps (1.x → 2.x). Prefer dedicated integration packages over `langchain-community`.

## Secrets & env vars

**All keys via BWS at runtime** (never plaintext, never committed):
```bash
export LITELLM_VIRTUAL_KEY="$(bws secret get <SECRET_ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGFUSE_PUBLIC_KEY="$(bws secret get <SECRET_ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGFUSE_SECRET_KEY="$(bws secret get <SECRET_ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
# or LangSmith:
export LANGSMITH_TRACING=true
export LANGSMITH_API_KEY="$(bws secret get <SECRET_ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGSMITH_PROJECT="<project-name>"
```
At IntegriBilt the **model provider key lives inside the gateway** (`/srv/core/litellm/config.yaml` on SVR02) — app code only needs the LiteLLM virtual key, not `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`.

> **TODO (fill in):** BWS secret IDs for `LITELLM_VIRTUAL_KEY`, `LANGFUSE_PUBLIC_KEY`,
> `LANGFUSE_SECRET_KEY`, `LANGSMITH_API_KEY`, and `TAVILY_API_KEY` (if Tavily is used).

## Common mistakes
- **Starting on 0.3** — `langchain>=0.3,<0.4` is legacy; use `>=1.0,<2.0`.
- **Unpinned `langchain-community`** — `>=0.4` can break; pin `>=0.4.0,<0.5.0`, or switch to a dedicated package.
- **Outdated community tool pins** — `langchain-tavily==0.0.1` breaks against 1.0; allow `>=0.1`.
- **Deprecated community imports** — prefer `from langchain_tavily import TavilySearch`, `from langchain_chroma import Chroma`, `from langchain_pinecone import PineconeVectorStore` over the `langchain_community.*` paths.
- **Missing `@langchain/core`** in TS monorepos — list it explicitly.
- **Python < 3.10 / Node < 20** — unsupported by 1.0.
