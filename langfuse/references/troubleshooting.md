# Troubleshooting & anti-patterns

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| No traces appear at all | Callback not enabled, or keys missing in the proxy env | Confirm `litellm_settings.success_callback` (classic) or `litellm_settings.callbacks` (otel) is set; confirm `LANGFUSE_PUBLIC_KEY`/`LANGFUSE_SECRET_KEY` are present in the container env (from BWS) |
| Traces from a script/CLI vanish | No flush before process exit (batches dropped) | Call `langfuse.flush()` before returning, or use a context manager; sync send for critical traces |
| `401` / auth error to Langfuse | Wrong key pair, or host doesn't match the keys' project | pk-lf-… is public, sk-lf-… is secret; `LANGFUSE_HOST`/`LANGFUSE_OTEL_HOST` must match the project the keys belong to |
| OTEL exporter connection refused (self-host) | SVR02 v3 backend (ClickHouse/Redis/blob) not stood up | Self-host is WIP — point `LANGFUSE_OTEL_HOST` at Langfuse Cloud until the backend is healthy (`self-hosting-svr02.md`) |
| Proxy crash-loops, Prisma `P1000: Authentication failed for ibops` | Bare `docker compose up` mis-parsed the special char in `POSTGRES_PASSWORD` | Recreate via `cd ~/integribilt-stack && ./start-stack.sh svr02 litellm-proxy` — never bare compose up |
| Proxy stuck `unhealthy`, never binds `:4000` | Unrelated: a `chatgpt/` OAuth device-flow model wedging startup past the healthcheck | Comment out the `chatgpt/*` model block in `/srv/core/litellm/config.yaml`, `docker restart` the proxy |
| Generations logged twice | SDK tracing AND gateway callback both active for the same call | Pick one layer — gateway callback OR SDK/handler — for the LLM generation |
| Costs/tokens missing on a generation | `usage` not provided (manual SDK) or model not priced | Pass `usage={"input":…, "output":…}` to `generation.end`; for the gateway, LiteLLM computes cost from its model map |
| Wrong/mixed traces under one id | Reused `trace_id` across unrelated requests | Use a unique `trace_id` per logical request; use `session_id` to group, not `trace_id` |
| Can't filter by user/session | Missing IDs | Always pass `trace_user_id`/`user_id` and `session_id` (gateway: in request `metadata`) |

## Verify ingestion quickly

```bash
curl -s http://192.168.254.2:4000/health/readiness          # gateway up?
# send a smoke call with metadata.tags=["smoke"], then look for it in Langfuse
```

If the gateway answers but Langfuse stays empty, it's almost always (a) callback
not actually set in the live config, or (b) keys not in the container env. Confirm
both before deeper debugging.

---

## Anti-patterns (from the source skill, kept)

### Not flushing in serverless
Traces are batched; a serverless/CLI process can exit before the batch ships, so
data is lost. **Always** `langfuse.flush()` at the end; use context managers where
available; consider sync mode for critical traces.

### Tracing everything
Noisy traces, performance overhead, important info buried. Trace **LLM calls, key
logic, and user actions** only. Group related operations and use meaningful span
names.

### No user/session IDs
Without them you can't debug a specific user, can't track sessions, and analytics
are limited. Always pass `user_id`/`trace_user_id` and `session_id` with consistent
identifiers, plus relevant metadata.

---

## IntegriBilt-specific reminders

- Secrets only via BWS; never cleartext in repo/compose/logs.
- Use explicit IP `192.168.254.2`, never `localhost`, for cross-host calls.
- One shared `docker-compose.yml` for the SVR02 stack; no extra compose files,
  no standalone `docker run` for managed services.
- Recreate DB-backed services with `./start-stack.sh svr02 <service>`.
- Self-host is WIP — default to Langfuse Cloud until the SVR02 v3 backend is up.

---

Source: anti-patterns consolidated from `c-skills/langfuse` and
`awesome-skills/langfuse` (vibeship-spawner-skills, Apache 2.0); IntegriBilt
operational notes added 2026-06-28.
