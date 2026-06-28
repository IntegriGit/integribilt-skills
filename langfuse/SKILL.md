---
name: langfuse
description: >-
  Langfuse LLM observability for IntegriBilt's lang-family suite — tracing,
  prompt management, evaluation, datasets, and LangChain/LangGraph/OpenAI
  integration. Use when tracing or observing LLM input/output in Langfuse,
  managing or versioning prompts, running evals or datasets, self-hosting
  Langfuse on SVR02, or wiring Langfuse into the IntegriBilt LiteLLM gateway
  (http://192.168.254.2:4000) via the classic `langfuse` callback or the
  `langfuse_otel` OpenTelemetry callback. Triggers: langfuse, llm observability,
  llm tracing, prompt management, llm evaluation, monitor/debug llm, langfuse
  callback, langfuse_otel, langfuse self-host.
risk: read-write
source: >-
  Consolidated from awesome-skills/langfuse and c-skills/langfuse
  (vibeship-spawner-skills, Apache 2.0); IntegriBilt LiteLLM-gateway and
  SVR02 self-host facts added 2026-06-28.
date_added: 2026-06-28
---

# Langfuse

Langfuse is the open-source LLM observability platform: traces, spans, and
generations for every LLM call, plus prompt management, evaluation, scoring, and
datasets. At IntegriBilt the primary way Langfuse gets populated is **through the
LiteLLM gateway** (`http://192.168.254.2:4000` on SVR02) — turn on a callback and
every model call across the fleet is observed without touching app code. You can
also instrument apps directly with the Python/JS SDK.

This skill covers, in priority order for IntegriBilt:

1. **LiteLLM gateway integration** — classic `langfuse` callback and the v3
   `langfuse_otel` OpenTelemetry callback (the key IntegriBilt angle).
2. **Self-hosting Langfuse on SVR02** — partially stood up, v3 backend is WIP.
3. Direct SDK tracing, prompt management, evaluation/datasets, and LangChain.

**Role**: LLM Observability Architect. Think in traces, spans, generations, and
scores. LLM apps need monitoring like any software, but on extra axes — cost,
quality, latency. Use the data to drive prompt improvements and catch regressions.

## Secrets — always via BWS, never plaintext

Langfuse auth is two keys plus a host. **Never hardcode or echo them.** Pull at
runtime from Bitwarden Secrets Manager:

```bash
export LANGFUSE_PUBLIC_KEY="$(bws secret get <ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"  # pk-lf-...
export LANGFUSE_SECRET_KEY="$(bws secret get <ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"  # sk-lf-...
export LANGFUSE_HOST="https://cloud.langfuse.com"   # or the SVR02 self-host URL
```

> **TODO (fill in):** BWS secret ID for `LANGFUSE_PUBLIC_KEY` (pk-lf-…).
> **TODO (fill in):** BWS secret ID for `LANGFUSE_SECRET_KEY` (sk-lf-…).
> **TODO (fill in):** BWS secret ID for `LANGFUSE_HOST` if self-hosted (else default cloud).

The LiteLLM proxy reads these as plain env vars in its container environment.
In the shared `docker-compose.yml` they should be injected from `.env` (which is
populated from BWS), not committed in cleartext. See
[references/litellm-gateway-integration.md](references/litellm-gateway-integration.md).

---

## LiteLLM gateway integration (the IntegriBilt path)

This is how Langfuse is meant to be fed at IntegriBilt: flip a callback on the
gateway and every request routed through `http://192.168.254.2:4000` is traced —
including cost and token usage, which LiteLLM computes and forwards. Two options.

### Option A — classic `langfuse` callback (Langfuse v2-style ingestion)

**Library mode** (when calling `litellm` directly in code):

```python
import litellm
litellm.success_callback = ["langfuse"]
litellm.failure_callback = ["langfuse"]   # log failed calls too
```

**Proxy mode (our gateway)** — `/srv/core/litellm/config.yaml`:

```yaml
litellm_settings:
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]   # optional but recommended
```

Required env in the proxy container: `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`,
and `LANGFUSE_HOST` (defaults to `https://cloud.langfuse.com` if unset).

### Option B — `langfuse_otel` OpenTelemetry callback (PREFERRED for Langfuse v3)

For Langfuse **v3**, prefer the OpenTelemetry integration. It ships traces over
OTLP rather than the legacy ingestion API.

```python
import litellm
litellm.callbacks = ["langfuse_otel"]
```

Proxy `config.yaml`:

```yaml
litellm_settings:
  callbacks: ["langfuse_otel"]
```

Required env: `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`, `LANGFUSE_OTEL_HOST`.

What LiteLLM does under the hood:

- Endpoint resolves to `{LANGFUSE_OTEL_HOST}/api/public/otel`.
- Auth header = HTTP Basic, `base64("public_key:secret_key")`.
- It sets `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_HEADERS` for you.
- Optional: `OTEL_IGNORE_CONTEXT_PROPAGATION=true` to stop LiteLLM joining an
  inbound trace context (use when callers send their own OTEL headers and you
  want each gateway call as its own root trace).

For the SVR02 self-host the OTEL host would be the SVR02 Langfuse URL and the
endpoint `https://<svr02-langfuse-host>/api/public/otel` — but see the WIP caveat
in the self-hosting section before relying on it.

### Per-request metadata (works with the classic callback)

Attach trace context per call by passing a `metadata` block in the request body
(OpenAI-compatible clients pass it through; the gateway maps it to Langfuse):

```python
response = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello"}],
    extra_body={
        "metadata": {
            "generation_name": "support-reply",   # names the generation
            "trace_id": "trace-abc-123",            # group calls into one trace
            "trace_user_id": "user-456",
            "trace_metadata": {"feature": "front-counter"},
            "trace_version": "v2",
            "trace_release": "2026.06.0",
            "tags": ["production", "spruce"],
        }
    },
)
```

Restart the proxy the **safe** way after editing `config.yaml` — never a bare
`docker compose up` (it mis-parses `POSTGRES_PASSWORD` and crash-loops Prisma
with `P1000`):

```bash
cd ~/integribilt-stack && ./start-stack.sh svr02 litellm-proxy
```

Full callback/env/restart detail, plus a verification checklist:
[references/litellm-gateway-integration.md](references/litellm-gateway-integration.md).

---

## Self-hosting Langfuse on SVR02 (WORK IN PROGRESS)

Langfuse is being self-hosted on SVR02 (`192.168.254.2`) inside the shared
`docker-compose.yml` at `/home/lmiller/integribilt-stack/`.

> **WORK IN PROGRESS — do not point production traffic at the self-host yet.**
> Langfuse **v3 requires a full backend that is not stood up**: a **ClickHouse**
> OLAP store (events/observations), **Redis** (queue/cache), and **blob/S3-style
> object storage** (event payloads). Until those three exist and are wired, the
> Langfuse container will not ingest correctly. The container is currently
> **parked**, and its **host port was moved to 3016** to free the previous port.

What is true today:

- Container exists in the shared compose stack but is parked.
- Host port: **3016** (was reassigned off its old port).
- If/when v3 is fully wired, the self-hosted **OTEL endpoint** would be
  `https://<svr02-langfuse-host>/api/public/otel` and `LANGFUSE_OTEL_HOST` would
  point at the SVR02 Langfuse URL.

> **TODO (fill in as we learn):** stand up ClickHouse + Redis + blob storage for
> Langfuse v3 in the shared compose stack (profile `svr02`); never add a separate
> compose file — extend the shared one. Then un-park the Langfuse service.
> **TODO (fill in):** final self-host hostname / reverse-proxy URL for SVR02 Langfuse.
> **TODO (fill in):** which Redis — reuse the existing stack Redis (mind DB index 7
> reserved for agent state) or a dedicated instance.

Until the self-host is healthy, use **Langfuse Cloud** (`https://cloud.langfuse.com`)
as the host for the gateway callbacks above. Architecture, the v3 component
breakdown, and a bring-up checklist:
[references/self-hosting-svr02.md](references/self-hosting-svr02.md).

---

## Direct SDK tracing & spans

When you want spans inside app code (not just gateway-level traces), use the SDK.
A **trace** is one request; **generations** are LLM calls; **spans** are other
steps (retrieval, tool calls). Scores attach quality/feedback to a trace.

```python
from langfuse import Langfuse

langfuse = Langfuse()  # reads LANGFUSE_PUBLIC_KEY / _SECRET_KEY / _HOST from env

trace = langfuse.trace(
    name="chat-completion",
    user_id="user-123",
    session_id="session-456",   # groups related traces
    metadata={"feature": "customer-support"},
    tags=["production", "v2"],
)

generation = trace.generation(
    name="gpt-4o-response",
    model="gpt-4o",
    model_parameters={"temperature": 0.7},
    input={"messages": [{"role": "user", "content": "Hello"}]},
)
# ... make the actual LLM call ...
generation.end(
    output=response_text,
    usage={"input": prompt_tokens, "output": completion_tokens},
)

trace.score(name="user-feedback", value=1, comment="User clicked helpful")
langfuse.flush()   # REQUIRED before exit in serverless / short-lived processes
```

**Decorator pattern** for clean, nested instrumentation — `@observe()` makes a
trace at the top and spans for nested calls; `@observe(as_type="generation")`
marks an LLM call. Use `langfuse_context.update_current_trace(...)` and
`langfuse_context.score_current_trace(...)` inside. Full examples (sync, async,
streaming, OpenAI drop-in `from langfuse.openai import openai`):
[references/tracing-and-sdk.md](references/tracing-and-sdk.md).

> Note: if calls already route through the gateway with a callback enabled,
> you usually do **not** also need SDK tracing — pick one to avoid double-logging.

---

## Prompt management

Version prompts in Langfuse and fetch them at runtime by label, decoupling prompt
changes from deploys.

```python
from langfuse import Langfuse
langfuse = Langfuse()

# Create / update (labels gate which version each env gets)
langfuse.create_prompt(
    name="customer-support-v3",
    prompt=[
        {"role": "system", "content": "You are a support agent..."},
        {"role": "user", "content": "{{user_message}}"},
    ],
    config={"model": "gpt-4o", "temperature": 0.7},
    labels=["production"],          # or ["staging"], ["development"]
)

# Fetch the production version, compile with variables
prompt = langfuse.get_prompt("customer-support-v3", label="production")
compiled = prompt.compile(user_message="How do I reset my password?")

# Link the resulting generation back to the prompt version for analytics
generation = trace.generation(name="response", model="gpt-4o", prompt=prompt)
```

Caching, fallbacks, and linking prompts to generations:
[references/prompt-management.md](references/prompt-management.md).

---

## Evaluation & datasets

Score traces (manually, via LLM-as-judge, or programmatically) and run regression
evals against curated datasets.

```python
# Scoring a trace
trace.score(name="relevance", value=0.85, comment="Addressed the question")
trace.score(name="correctness", value=1, data_type="BOOLEAN")

# Dataset-driven eval
langfuse.create_dataset(name="support-qa-v1")
langfuse.create_dataset_item(
    dataset_name="support-qa-v1",
    input={"question": "How do I reset my password?"},
    expected_output="Go to settings > security > reset password",
)

dataset = langfuse.get_dataset("support-qa-v1")
for item in dataset.items:
    response = generate_response(item.input["question"])
    trace = langfuse.trace(name="eval-run")
    trace.generation(name="response", input=item.input, output=response)
    trace.score(name="similarity",
                value=calculate_similarity(response, item.expected_output))
    item.link(trace, "eval-run-1")   # ties trace to the dataset item
```

LLM-as-judge scaffolding, score data types, and CI eval loops:
[references/evaluation-and-datasets.md](references/evaluation-and-datasets.md).

---

## LangChain / LangGraph callback handler

For LangChain or LangGraph apps, attach the Langfuse callback handler — it traces
chains, agents, tools, and retrievers automatically.

```python
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
from langfuse.callback import CallbackHandler

langfuse_handler = CallbackHandler(session_id="session-123", user_id="user-456")
# keys/host come from env (BWS) — do not pass literals

chain = ChatPromptTemplate.from_messages(
    [("system", "You are a helpful assistant."), ("user", "{input}")]
) | ChatOpenAI(model="gpt-4o")

response = chain.invoke({"input": "Hello"}, config={"callbacks": [langfuse_handler]})
```

The same handler goes into `AgentExecutor.invoke(..., config={"callbacks": [...]})`
and LangGraph `graph.invoke(..., config={"callbacks": [...]})`. Pair Langchain
LLMs with the IntegriBilt gateway by pointing `ChatOpenAI(base_url=...)` at
`http://192.168.254.2:4000`. Full LangGraph agent + RAG examples:
[references/langchain-langgraph.md](references/langchain-langgraph.md).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| No traces appear at all | Callback not enabled, or keys missing in proxy env | Confirm `litellm_settings.success_callback`/`callbacks` set; confirm `LANGFUSE_PUBLIC_KEY`/`_SECRET_KEY` in the container env (from BWS) |
| Traces from a script vanish | No flush before process exit | Call `langfuse.flush()` (or use a context manager) before returning |
| `401`/auth errors to Langfuse | Wrong key pair or wrong host | pk-lf-… is public, sk-lf-… is secret; verify `LANGFUSE_HOST` / `LANGFUSE_OTEL_HOST` matches the keys' project |
| OTEL exporter connection refused (self-host) | v3 backend (ClickHouse/Redis/blob) not up | Self-host is WIP — use Langfuse Cloud until SVR02 backend is stood up |
| Proxy crash-loops after editing `config.yaml` (Prisma `P1000`) | Bare `docker compose up` mis-parsed `POSTGRES_PASSWORD` | Recreate via `./start-stack.sh svr02 litellm-proxy`, not bare compose |
| Proxy stuck `unhealthy`, never binds :4000 | Unrelated wedge — a `chatgpt/` device-flow model in config | Comment out the OAuth model block, `docker restart` the proxy |
| Noisy / unreadable traces | Tracing everything | Trace LLM calls + key logic only; use meaningful span names |
| Can't debug a specific user/session | Missing IDs | Always pass `trace_user_id` / `user_id` and `session_id` |
| Double-logged generations | SDK tracing AND gateway callback both on | Pick one layer (gateway callback OR SDK) |

More: [references/troubleshooting.md](references/troubleshooting.md).

---

## References

- [references/litellm-gateway-integration.md](references/litellm-gateway-integration.md) — classic `langfuse` + `langfuse_otel` callbacks, config.yaml, env, per-request metadata, restart, verification.
- [references/self-hosting-svr02.md](references/self-hosting-svr02.md) — SVR02 self-host status (WIP), v3 ClickHouse/Redis/blob backend, bring-up checklist, port 3016.
- [references/tracing-and-sdk.md](references/tracing-and-sdk.md) — SDK init, traces/spans/generations, decorators, OpenAI drop-in, async/streaming, flushing.
- [references/prompt-management.md](references/prompt-management.md) — create/version/fetch prompts, labels, compile, caching, link to generations.
- [references/evaluation-and-datasets.md](references/evaluation-and-datasets.md) — scoring, LLM-as-judge, datasets, CI eval loop.
- [references/langchain-langgraph.md](references/langchain-langgraph.md) — callback handler, agents, RAG, LangGraph, gateway base_url.
- [references/troubleshooting.md](references/troubleshooting.md) — extended failure modes and anti-patterns.

Sources consolidated: `awesome-skills/langfuse/SKILL.md` and
`c-skills/langfuse/SKILL.md` (both from vibeship-spawner-skills, Apache 2.0).
IntegriBilt gateway and SVR02 self-host facts current as of 2026-06-28.
