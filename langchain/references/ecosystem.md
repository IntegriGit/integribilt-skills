# Ecosystem — LangChain vs LangGraph vs Deep Agents

> Built from the official `ecosystem-primer` skill. Read this first when scoping
> any agent-building project to pick the right layer before writing code.

## The stack (top-down)

LangChain Inc. maintains three layered open-source tools plus an observability layer:

- **Deep Agents** (top, *harness*) — batteries-included toolkit on LangChain + LangGraph. Planning, file management, subagent spawning, memory out of the box.
- **LangGraph** (middle, *runtime*) — low-level orchestration for durable execution, custom control flow, stateful workflows. LangChain agents run on top of it.
- **LangChain** (bottom, *framework*) — abstractions for models, tools, and the agent loop. Provider-agnostic, easiest to start with.
- **LangSmith / Langfuse** (cross-cutting) — observability and evaluation. Framework-agnostic; always recommended.

Higher layers depend on lower ones, but you don't use lower layers directly. Deep Agents gives you LangGraph's durable execution without graph code; LangChain gives you models and tools without managing edges.

## Decision table

Evaluate in order, stop at the first match:

1. Needs planning, file management across a long session, persistent memory, subagent delegation, or on-demand skills → **Deep Agents** (`create_deep_agent(...)`)
2. Else needs custom control flow (deterministic loops, branching) → **LangGraph** (`StateGraph(State)`) — see sibling `langgraph` skill
3. Else single-purpose agent with a fixed tool set → **LangChain** `create_agent(...)`
4. Else pure model call, retrieval pipeline, or simple chain → **LangChain** direct model/chain

## Tool profiles

**LangChain** — best for single-purpose agents, RAG / doc Q&A, model calls / structured output. Not ideal when the agent must plan across many steps, control flow is conditional/iterative/parallel, or state must persist across sessions.

**LangGraph** — best for custom control flow (loops, reflection cycles, parallel fan-out), mixed deterministic+agentic workflows, precise HITL interrupt/resume, and state that survives failures or long sessions. Not ideal when you want planning/files/subagents out of the box (use Deep Agents) or the workflow is a simple tool loop.

**Deep Agents** — best for long-running tasks needing planning/decomposition, file read/write/manage across a session, subagent delegation, persistent cross-session memory, on-demand skills. Not ideal when the task is a single-purpose agent or you need hand-crafted control over every graph edge.

## Mixing layers

The tools are layered, so they combine in one project:
- **Deep Agents orchestrator → LangGraph subagent** — main agent plans/remembers; one subtask needs a deterministic graph.
- **LangGraph graph wrapped as a tool/subagent** — a specialized pipeline (RAG, reflection loop) called by a broader agent.

A compiled LangGraph graph can register as a named subagent in Deep Agents — the orchestrator delegates via the `task` tool without knowing the internals. LangChain tools and retrievers work freely inside both LangGraph nodes and Deep Agents tools.

## Environment (IntegriBilt)

Set observability env (current LangSmith names; older names no longer work) — pull keys from BWS, never plaintext:
```bash
export LANGSMITH_API_KEY="$(bws secret get <SECRET_ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGSMITH_TRACING=true
export LANGSMITH_PROJECT="<project-name>"
```
Or use self-hosted **Langfuse** (preferred at IntegriBilt — keeps trace data in-house). The model key lives in the LiteLLM Gateway, so app code only needs the LiteLLM virtual key — see SKILL.md.

## Docs map

All docs at **docs.langchain.com**, two top-level sections:
- **OSS** — LangChain, LangGraph, Deep Agents. Python (`/oss/python/`) and TypeScript (`/oss/javascript/`) trees in parallel.
- **LangSmith** — observability, evaluation, deployment.

Canonical landing pages (swap `python`→`javascript` for TS):
- LangChain — `/oss/python/langchain/overview`
- LangGraph — `/oss/python/langgraph/overview`
- Deep Agents — `/oss/python/deepagents/overview`
- LangSmith — `/langsmith/home` (no language split)

If the LangChain Docs MCP server is connected (`mcp__docs-langchain__*`), query it directly (`tree`, `cat`, `rg`). Otherwise fetch `https://docs.langchain.com/llms.txt`, pick the 2–4 most relevant pages, and fetch those. **Always prefer live docs over training-data recall** — these libraries change often.

## Where to go next (sibling skills)

- **`langchain`** (this skill) — `create_agent`, tools, middleware, RAG.
- **`langgraph`** — custom graphs, durable execution, graph-level HITL/persistence.
- **`langfuse`** / **`langsmith`** — observability backend setup.
- **`integribilt-infrastructure`** — LiteLLM Gateway / SVR02 ops, BWS secret handling.

> **TODO (fill in as we learn):** whether Deep Agents (`deepagents`) is in use at
> IntegriBilt and whether a dedicated `deep-agents` sibling skill exists; the
> LangChain Docs MCP server connection status on the fleet.
