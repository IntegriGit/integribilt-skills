# LiteLLM → LangSmith (gateway callback)

The IntegriBilt-specific path: route LLM observability through the self-hosted LiteLLM gateway so **every model
call is traced in LangSmith with no application changes**.

- Gateway: `http://192.168.254.2:4000` (SVR02)
- Shared config: `/srv/core/litellm/config.yaml`
- LangSmith UI: https://smith.langchain.com

This is the inverse of the `litellm-skill-manager` skill (which *publishes skills to* the gateway); here we wire
an *observability callback* into the gateway.

## How it works

LiteLLM supports a `langsmith` callback. When enabled, after each completion the proxy serializes the request
and response into a LangSmith run and uploads it (batched). One callback = fleet-wide tracing for anything that
calls the gateway.

## Proxy configuration

Edit `/srv/core/litellm/config.yaml` and add the callback under `litellm_settings`:

```yaml
litellm_settings:
  callbacks: ["langsmith"]
  # langsmith_batch_size: 1   # uncomment for local testing only (see below)
```

Provide env to the proxy container, sourced from BWS — never inline plaintext:

```bash
LANGSMITH_API_KEY=<from BWS>           # bws secret get <ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value
LANGSMITH_PROJECT=litellm-completion   # default if unset; override per environment
LANGSMITH_DEFAULT_RUN_NAME=LLMRun      # run name shown in LangSmith; default LLMRun
```

> **TODO (fill in):** BWS secret ID for the LangSmith API key.

## Standalone SDK (no gateway)

For a one-off local script that embeds the LiteLLM SDK directly:

```python
import litellm
litellm.callbacks = ["langsmith"]
# env: LANGSMITH_API_KEY, LANGSMITH_PROJECT, LANGSMITH_DEFAULT_RUN_NAME
resp = litellm.completion(
    model="gpt-4o-mini",
    messages=[{"role": "user", "content": "ping"}],
)
```

## Batching

`litellm.langsmith_batch_size` controls how many runs buffer before upload. **Default 512.** During local
testing that means traces appear to "not work" until the buffer flushes — set it to **1** so each call lands
immediately:

```python
litellm.langsmith_batch_size = 1            # SDK
```

```yaml
litellm_settings:
  callbacks: ["langsmith"]
  langsmith_batch_size: 1                    # proxy, testing only
```

Raise it back to the default (or higher) for production throughput. Batch size 1 is a debugging aid, not a
production setting.

## Restart the gateway (the approved way)

Recreate the proxy via the stack script — **never** a bare `docker compose up`, which breaks
`POSTGRES_PASSWORD` parsing and DB auth (see the LiteLLM restart memory note and the
`integribilt-infrastructure` skill).

```bash
# on SVR02, stack path /home/lmiller/integribilt-stack/
./start-stack.sh
# or the profile form if that is the documented path:
# docker compose --profile svr02 up -d
```

## Verify

1. Make one model call through the gateway:
   ```bash
   curl -s http://192.168.254.2:4000/v1/chat/completions \
     -H "Authorization: Bearer <gateway virtual key from BWS>" \
     -H "Content-Type: application/json" \
     -d '{"model":"<a configured model>","messages":[{"role":"user","content":"trace test"}]}' >/dev/null
   ```
2. Open https://smith.langchain.com, select the `litellm-completion` project, and confirm a fresh `LLMRun`
   trace with inputs/outputs and token/cost metadata.
3. Or query from the CLI:
   ```bash
   langsmith trace list --project litellm-completion --last-n-minutes 5 --include-metadata
   ```

If nothing shows: check batch size (testing), that the key reached the container, and that you recreated the
proxy via `start-stack.sh`.

## Rollback

Remove `langsmith` from the `callbacks` list in `/srv/core/litellm/config.yaml` (or revert the file) and
recreate the proxy via `start-stack.sh`. No data migration is involved — the callback is fire-and-forget; once
removed, no further traces are emitted. Existing traces remain in LangSmith.

## Notes

- The gateway callback observes **raw completions**. For agent/graph trajectory structure, also run the
  LangSmith SDK inside the app (`references/sdk-tracing.md`) — the two compose.
- Managed Deep Agents do **not** route through this gateway, so this callback does not see them.
