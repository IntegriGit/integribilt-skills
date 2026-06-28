# LiteLLM gateway → Langfuse integration (IntegriBilt)

The IntegriBilt LiteLLM gateway runs on **SVR02** at `http://192.168.254.2:4000`.
Enabling a Langfuse callback there means every request routed through the gateway
— from any host, any client, any model — lands in Langfuse with cost, tokens,
latency, input, and output. This is the primary observability path at IntegriBilt;
prefer it over per-app SDK instrumentation.

Config file (live, bind-mounted into the proxy container as
`/app/config/config.yaml`): **`/srv/core/litellm/config.yaml`**.

---

## 1. Classic `langfuse` callback

### Library mode (calling `litellm` in Python directly)

```python
import litellm

litellm.success_callback = ["langfuse"]
litellm.failure_callback = ["langfuse"]   # also log failed / errored calls

response = litellm.completion(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Hello"}],
)
```

### Proxy mode (the gateway)

Add to `/srv/core/litellm/config.yaml`:

```yaml
litellm_settings:
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]   # optional but recommended
```

### Required environment (proxy container)

| Var | Value | Notes |
|---|---|---|
| `LANGFUSE_PUBLIC_KEY` | `pk-lf-…` | from BWS |
| `LANGFUSE_SECRET_KEY` | `sk-lf-…` | from BWS |
| `LANGFUSE_HOST` | `https://cloud.langfuse.com` | default if unset; set to SVR02 URL when self-host is live |

Inject from `.env` (populated from BWS), never as cleartext literals in
`docker-compose.yml`:

```bash
export LANGFUSE_PUBLIC_KEY="$(bws secret get <ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGFUSE_SECRET_KEY="$(bws secret get <ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGFUSE_HOST="https://cloud.langfuse.com"
```

> **TODO (fill in):** BWS secret IDs for `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_SECRET_KEY`,
> and (if self-hosted) `LANGFUSE_HOST` / `LANGFUSE_OTEL_HOST`.

---

## 2. `langfuse_otel` OpenTelemetry callback — PREFERRED for Langfuse v3

Langfuse v3 ingests over OTLP. Use the OTEL callback instead of the classic one.

### Library mode

```python
import litellm
litellm.callbacks = ["langfuse_otel"]
```

### Proxy mode

```yaml
litellm_settings:
  callbacks: ["langfuse_otel"]
```

### Required environment

| Var | Value |
|---|---|
| `LANGFUSE_PUBLIC_KEY` | `pk-lf-…` (BWS) |
| `LANGFUSE_SECRET_KEY` | `sk-lf-…` (BWS) |
| `LANGFUSE_OTEL_HOST` | Langfuse host base (cloud or SVR02) |

### What LiteLLM does under the hood

- Resolves the OTLP endpoint to `{LANGFUSE_OTEL_HOST}/api/public/otel`.
- Builds the auth header as HTTP **Basic** = `base64("public_key:secret_key")`.
- Sets `OTEL_EXPORTER_OTLP_ENDPOINT` and `OTEL_EXPORTER_OTLP_HEADERS` for you —
  you do not set those manually.

### Optional OTEL knob

- `OTEL_IGNORE_CONTEXT_PROPAGATION=true` — stop LiteLLM from joining an inbound
  trace context. Use when upstream callers already send OTEL headers and you want
  each gateway call to be its own root trace rather than a child span.

### Self-host endpoint (when SVR02 v3 is live)

```
LANGFUSE_OTEL_HOST = https://<svr02-langfuse-host>
# endpoint => https://<svr02-langfuse-host>/api/public/otel
```

See `self-hosting-svr02.md` — the v3 backend (ClickHouse + Redis + blob storage)
is **not yet stood up**, so until then point `LANGFUSE_OTEL_HOST` at Langfuse Cloud.

---

## 3. Per-request metadata (classic callback)

Pass a `metadata` object in the request body. With OpenAI-compatible clients use
`extra_body`; raw HTTP clients put it at the top level of the JSON body. The
gateway maps these keys into the Langfuse trace/generation:

| Metadata key | Effect in Langfuse |
|---|---|
| `generation_name` | Names the generation (the LLM call) |
| `trace_id` | Explicit trace id — reuse to group several calls into one trace |
| `trace_user_id` | Sets the trace's user |
| `trace_metadata` | Arbitrary object attached to the trace |
| `trace_version` | Trace version label |
| `trace_release` | Release tag (e.g. app build) |
| `tags` | List of trace tags for filtering |

```python
from openai import OpenAI
client = OpenAI(base_url="http://192.168.254.2:4000", api_key="<litellm-virtual-key>")

resp = client.chat.completions.create(
    model="gpt-4o",
    messages=[{"role": "user", "content": "Summarize this invoice"}],
    extra_body={
        "metadata": {
            "generation_name": "invoice-summary",
            "trace_id": "front-counter-2026-06-28-001",
            "trace_user_id": "lester",
            "trace_metadata": {"app": "spruce-assist", "host": "OFC01"},
            "trace_version": "v1",
            "trace_release": "2026.06.0",
            "tags": ["production", "spruce", "front-counter"],
        }
    },
)
```

> The LiteLLM virtual key (not the upstream provider key) is what clients send to
> the gateway. Pull it from BWS; never hardcode. Use the explicit IP
> `192.168.254.2`, never `localhost`, for cross-host calls.

---

## 4. Restart the proxy the safe way

After editing `/srv/core/litellm/config.yaml`, recreate the proxy via the start
script — it `source`s `.env` first so the special character in `POSTGRES_PASSWORD`
parses correctly. A bare `docker compose up` mis-parses it and crash-loops Prisma
with `P1000: Authentication failed for ibops`.

```bash
cd ~/integribilt-stack && ./start-stack.sh svr02 litellm-proxy
```

A plain `docker restart integribilt-stack-litellm-proxy-1` (preserves env) is also
safe for a config reload. Never bare `docker compose --profile svr02 up -d
litellm-proxy`.

---

## 5. Verify

```bash
# health (binds :4000 only when startup succeeded)
curl -s http://192.168.254.2:4000/health/readiness

# make one traced call, then confirm it shows in Langfuse
curl -s http://192.168.254.2:4000/v1/chat/completions \
  -H "Authorization: Bearer <litellm-virtual-key>" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"ping"}],
       "metadata":{"generation_name":"smoke-test","tags":["smoke"]}}'
```

Then check the Langfuse project (cloud dashboard or self-host UI) for a trace
named/tagged `smoke-test`/`smoke`. If nothing arrives, see `troubleshooting.md`
(usually missing keys in the container env or callback not actually set).

> Related gotcha: if the proxy is stuck `unhealthy` and never binds :4000, that is
> typically a `chatgpt/` OAuth device-flow model wedging startup — unrelated to
> Langfuse. Comment out that model block and `docker restart` the proxy.
