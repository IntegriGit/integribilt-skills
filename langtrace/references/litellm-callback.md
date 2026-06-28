# Langtrace ↔ LiteLLM callback wiring (reference)

> **EARLY / PARTIAL.** Confirmed facts and open questions are clearly separated.
> Do not promote a TODO to fact without checking https://langtrace.ai docs or
> the installed `langtrace-python-sdk`.

## Confirmed facts

- Langtrace enables in the **LiteLLM SDK** with:
  ```python
  from langtrace_python_sdk import langtrace
  import litellm

  langtrace.init()
  litellm.callbacks = ["langtrace"]
  ```
- In the **LiteLLM proxy** (the IntegriBilt gateway), enable via config:
  ```yaml
  litellm_settings:
    callbacks: ["langtrace"]
  ```
- Gateway: `http://192.168.254.2:4000` (SVR02, container
  `integribilt-stack-litellm-proxy-1`).
- Gateway config path: `/srv/core/litellm/config.yaml`.
- Langtrace is OpenTelemetry-based.

## Two integration modes

### A) Gateway (preferred at IntegriBilt)

Anything already calling `http://192.168.254.2:4000` gets tracing by flipping one
config switch — no app code change.

1. Edit `/srv/core/litellm/config.yaml`, add `"langtrace"` to
   `litellm_settings.callbacks` (append; don't clobber existing callbacks).
2. Ensure the proxy environment has:
   - the `langtrace-python-sdk` package in the image/venv;
   - the Langtrace API key env var (from BWS — see Secrets in SKILL.md);
   - (self-host only) the API host env var.
3. Restart the proxy the IntegriBilt way — recreate via `start-stack.sh`, **not**
   a bare `docker compose up` (breaks `POSTGRES_PASSWORD` parsing; see the
   `litellm-restart-method` memory note).
4. Verify (below).

### B) In-app SDK

For a standalone Python service using LiteLLM directly:

```python
from langtrace_python_sdk import langtrace
import litellm

langtrace.init()                  # OTEL exporter setup
litellm.callbacks = ["langtrace"]

resp = litellm.completion(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "hello"}],
)
```

If this app also routes through the gateway, decide deliberately whether to trace
at the **gateway** or the **app** layer to avoid duplicate/confusing nested
traces. (Both-on behavior is unconfirmed — test before relying on it.)

## Verify loop

1. Confirm the callback is loaded — gateway startup logs should show the
   `langtrace` callback registered (exact log line unconfirmed).
2. Make one completion call through the gateway/app.
3. Open the Langtrace project UI and confirm a fresh trace with at least one LLM
   span (model, tokens, latency).
4. If nothing appears, walk the Troubleshooting table in SKILL.md — start with
   "is the API-key env var set **inside the container**".

## Open questions (do not guess)

> **TODO (fill in as we learn):** exact **env var name** for the API key that
> both the proxy and SDK read (commonly `LANGTRACE_API_KEY`, **unconfirmed**).

> **TODO (fill in as we learn):** **`langtrace.init()` parameters** —
> `api_key=...` (vs env var) and `api_host=...` (self-host). Confirm kwarg names
> against the installed SDK version.

> **TODO (fill in as we learn):** in **proxy** mode, is `langtrace.init()`
> invoked automatically when the callback is enabled, or must it run in a startup
> hook?

> **TODO (fill in as we learn):** **per-request metadata** — can tags /
> session-id / user-id / arbitrary attributes be passed per request (e.g. via the
> LiteLLM request `metadata` field) and land as Langtrace span attributes?

> **TODO (fill in as we learn):** does the gateway image already bundle
> `langtrace-python-sdk`, or must it be added to the proxy dependencies?

## Secrets

Pull the key from BWS at use-time; never write it to disk in cleartext, never
echo it into a logged command:

```bash
export LANGTRACE_API_KEY="$(bws secret get <LANGTRACE_API_KEY_SECRET_ID> -t "$BWS_ACCESS_TOKEN" | jq -r '.value')"
```

> **TODO (fill in):** BWS secret ID for the Langtrace API key.
