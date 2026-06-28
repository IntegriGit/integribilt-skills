---
name: langtrace
description: "Use when wiring Langtrace LLM observability into the LiteLLM gateway or an LLM app — enabling the `langtrace` callback in /srv/core/litellm/config.yaml on the SVR02 gateway (192.168.254.2:4000), calling langtrace.init() in the LiteLLM SDK, understanding its OpenTelemetry (OTEL) nature, or comparing it to Langfuse-OTEL / LangSmith for trace/span LLM tracing. EARLY/PARTIAL skill — see the TODOs before relying on specifics."
---

# Langtrace (IntegriBilt LLM observability)

> **Status: EARLY / PARTIAL.** Langtrace source material is thin right now. The
> structure below is correct, but several specifics (exact env-var name,
> `init()` params, self-host endpoint, per-request metadata) are **not yet
> confirmed** and are flagged with `> **TODO (fill in as we learn):** …`.
> Do **not** treat a TODO line as fact. Prefer asking over guessing.

## Overview

[Langtrace AI](https://langtrace.ai) is an **OpenTelemetry (OTEL)-based LLM
observability platform** — "Monitor, evaluate & improve your LLM apps." It
captures LLM/agent calls as OTEL **traces** made of **spans** (one span per
LLM/tool/retrieval operation), enriched with GenAI semantic-convention
attributes (model, prompt, completion, token counts, latency, cost). Because it
speaks OTEL, it sits alongside — and overlaps conceptually with — the other
members of IntegriBilt's "lang-family" observability suite (Langfuse, LangSmith).

IntegriBilt wires Langtrace in two ways:

1. **Through the LiteLLM gateway** (preferred for anything that already routes
   through `http://192.168.254.2:4000`) — a one-line `callbacks` entry.
2. **Directly in a Python LLM app** via the `langtrace-python-sdk` callback +
   `langtrace.init()`.

Both ship the same OTEL trace data to a Langtrace backend (cloud SaaS, or a
self-hosted instance — see Self-host, mostly TODO).

## LiteLLM gateway integration (callback)

This is the IntegriBilt-standard path. The gateway already fronts every model;
turning on Langtrace is a `litellm_settings` callback in the gateway config.

**Config file (SVR02):** `/srv/core/litellm/config.yaml`

```yaml
litellm_settings:
  callbacks: ["langtrace"]
  # ... existing settings ...
```

- If `callbacks:` already exists (e.g. for another logger), **append**
  `"langtrace"` to the list rather than overwriting it.
- The gateway process must have the `langtrace-python-sdk` package available in
  its image/venv, and the Langtrace API key in its environment. **Do not
  hardcode the key in `config.yaml`** — inject it as an env var pulled from BWS
  (see Secrets).

> **TODO (fill in as we learn):** the exact environment variable name LiteLLM /
> the Langtrace SDK reads for the API key (commonly something like
> `LANGTRACE_API_KEY`, **unconfirmed**), and whether the gateway needs
> `LANGTRACE_API_HOST` set for a self-hosted backend.

> **TODO (fill in as we learn):** whether `langtrace.init()` is auto-called when
> the callback is enabled in proxy mode, or whether it must be invoked in a
> startup hook. In SDK mode it is explicit (see below); proxy behavior is
> **unconfirmed**.

**Restart the gateway** the IntegriBilt way after editing config — recreate the
proxy via `start-stack.sh`, never a bare `docker compose up` (that breaks
`POSTGRES_PASSWORD` parsing). See the `integribilt-infrastructure` skill for the
exact restart procedure and the `litellm-restart-method` memory note.

**Verify:** make one test call through the gateway, then confirm a new trace
appears in the Langtrace UI/project.

> **TODO (fill in as we learn):** per-request metadata support through LiteLLM —
> whether tags / session-id / user-id / custom attributes can be attached
> per-request (e.g. via the `metadata` field in the LiteLLM request body) and
> surface as Langtrace span attributes. **Unconfirmed.**

## LiteLLM SDK integration (in-app, Python)

For a standalone Python app using the LiteLLM SDK directly (not the gateway):

```python
from langtrace_python_sdk import langtrace
import litellm

langtrace.init()                      # initializes the OTEL exporter
litellm.callbacks = ["langtrace"]     # route LiteLLM events to Langtrace

resp = litellm.completion(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "ping"}],
)
```

- `langtrace.init()` sets up the OTEL tracer/exporter. The known-required call
  signature is `langtrace.init()` (no args). Additional params below are
  **unconfirmed**.

> **TODO (fill in as we learn):** `langtrace.init()` parameters —
> `api_key=` (vs. reading the env var), and `api_host=` for pointing at a
> self-hosted backend instead of the Langtrace cloud. Confirm exact kwarg names
> against the installed `langtrace-python-sdk` version before documenting them
> as real.

## OTEL nature & how it compares to siblings

Langtrace is **OpenTelemetry under the hood**, so the mental model is the same
distributed-tracing model used elsewhere in the toolbox:

- **Trace** — one end-to-end request/agent run.
- **Span** — one operation inside it (an LLM call, a tool call, a retrieval).
  Spans nest: a chain/agent span parents its child LLM and tool spans.
- **Attributes (tags)** — key/value pairs on a span. LLM platforms follow the
  OTEL **GenAI semantic conventions** (`gen_ai.*` — system, request model,
  response model, prompt/completion, token usage), so model name, token counts,
  latency, and cost ride along as span attributes.

For OTEL span/attribute background, read the sibling toolbox skills
`awesome-skills/distributed-tracing` (trace/span/context/sampling model) and
`awesome-skills/observability-engineer`. Those are **generic OTEL** — apply the
concepts, but keep Langtrace-specific claims grounded in Langtrace docs, not
inferred from Jaeger/Tempo behavior.

**Where Langtrace sits vs. the other lang-family observability skills:**

| Platform | Wiring into LiteLLM | Transport model | IntegriBilt skill |
|---|---|---|---|
| **Langtrace** | `callbacks: ["langtrace"]` | Native **OTEL** spans | this skill (`langtrace`) |
| **Langfuse** | `callbacks: ["langfuse"]` (also supports an OTEL/OTLP ingestion path) | Langfuse trace model **and** OTEL | `langfuse` *(planned sibling — not yet authored)* |
| **LangSmith** | `callbacks: ["langsmith"]` | LangSmith run tree (OTEL export available) | `langsmith` *(planned sibling — not yet authored)* |

All three are LLM-call observers attachable as LiteLLM callbacks; the practical
difference is the backend and its native data model. Langtrace's differentiator
is that it is **OTEL-native end to end**, so it interoperates with any
OTEL-compatible collector/backend.

> **NOTE:** the `langfuse` and `langsmith` skills are referenced by the
> `litellm-skill-manager` skill as part of the same suite but are **not yet
> authored** in `integribilt-skills/`. Cross-links above are forward references,
> not existing files. Update them to real paths once those skills land.

## Self-host on SVR02 (mostly TODO)

IntegriBilt prefers self-hosting observability on the shared SVR02 stack rather
than sending traces to a third-party SaaS. Langtrace publishes a self-hostable
backend, but the IntegriBilt deployment is **not yet stood up or verified**.

> **TODO (fill in as we learn):** whether Langtrace will be self-hosted on SVR02
> at all (decision pending), and if so:
> - the service definition in the **shared** `/home/lmiller/integribilt-stack/docker-compose.yml` under the `svr02` profile (never a standalone compose file or `docker run` — see `integribilt-infrastructure`);
> - the resulting **endpoint** (expected form `http://192.168.254.2:<port>`, port **unconfirmed**);
> - the value to set for `LANGTRACE_API_HOST` / `langtrace.init(api_host=...)` so the gateway and apps target the self-hosted backend instead of `langtrace.ai`.

Until then, assume Langtrace points at the **cloud** backend (`langtrace.ai`)
and an account/project API key is required.

## Secrets (BWS — never plaintext)

The Langtrace API key is a secret. Retrieve it from Bitwarden Secrets Manager at
use-time; never hardcode it in `config.yaml`, never echo it into a task log:

```bash
export LANGTRACE_API_KEY="$(bws secret get <LANGTRACE_API_KEY_SECRET_ID> -t "$BWS_ACCESS_TOKEN" | jq -r '.value')"
```

> **TODO (fill in):** BWS secret ID for the Langtrace API key. Once created in
> BWS, record the ID here and replace `<LANGTRACE_API_KEY_SECRET_ID>`.

> **TODO (fill in as we learn):** confirm the env-var name the SDK/gateway
> actually reads (see the LiteLLM-gateway TODO above) so this `export` targets
> the right variable.

## Troubleshooting

| Symptom | Likely cause | Cheapest check |
|---|---|---|
| No traces appear after a gateway call | Callback not loaded, or API key/env var missing in the proxy environment | Confirm `langtrace` is in `litellm_settings.callbacks`; confirm the key env var is set **inside the proxy container**, not just the host |
| Gateway unhealthy / won't start after edit | YAML mistake in `config.yaml`, or restarted with bare `docker compose up` | Validate YAML; restart via `start-stack.sh` (see `litellm-restart-method` memory) |
| Traces go to cloud, not self-host | `api_host` / `LANGTRACE_API_HOST` unset → defaults to `langtrace.ai` | Set the host once the self-host endpoint exists (Self-host TODO) |
| `langtrace_python_sdk` import error | Package not in the gateway image/venv | Add `langtrace-python-sdk` to the proxy's deps |
| Spans missing token/cost data | Model/provider not emitting usage, or attribute mapping gap | Verify the model returns usage; check Langtrace GenAI-attribute support for that provider |

If stuck after the cheap checks, stop and report what was tried / learned /
blocker rather than thrashing (IntegriBilt failure etiquette).

## References

- `references/litellm-callback.md` — gateway + SDK callback wiring, the open
  env-var/init questions, and the verify loop.
- `references/otel-and-comparison.md` — OTEL span/attribute model for LLM traces
  and the Langtrace vs. Langfuse-OTEL vs. LangSmith comparison.
- External: Langtrace AI — https://langtrace.ai (authoritative source; consult
  before resolving any TODO above).
- Sibling toolbox skills for OTEL background: `awesome-skills/distributed-tracing`,
  `awesome-skills/observability-engineer`.
- IntegriBilt infra context: `integribilt-infrastructure` skill;
  `litellm-skill-manager` skill (the inverse — publishing skills *to* the gateway).

## Open items (consolidated)

- [ ] Exact API-key **env var name** (LiteLLM proxy + SDK).
- [ ] `langtrace.init()` **params** (`api_key`, `api_host`) — confirm against installed SDK version.
- [ ] Whether `init()` is needed/auto in **proxy** mode.
- [ ] **Self-host on SVR02**: decision, compose service, endpoint/port.
- [ ] **Per-request metadata** (tags/session/user) through LiteLLM → Langtrace spans.
- [ ] **BWS secret ID** for the Langtrace API key.
- [ ] Replace forward-reference cross-links once `langfuse` / `langsmith` skills are authored.
