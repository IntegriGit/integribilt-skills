# Self-hosting Langfuse on SVR02 — STATUS: WORK IN PROGRESS

Langfuse is being self-hosted on **SVR02** (`192.168.254.2`) inside the shared
`docker-compose.yml` at `/home/lmiller/integribilt-stack/`. It is **not yet
production-ready** — the Langfuse v3 backend it requires is not stood up.

> **Do not point gateway traffic at the SVR02 self-host yet.** Use Langfuse Cloud
> (`https://cloud.langfuse.com`) for `LANGFUSE_HOST` / `LANGFUSE_OTEL_HOST` until
> the backend below is healthy.

---

## Current state (2026-06-28)

- Langfuse container **exists** in the shared compose stack but is **parked**
  (not serving).
- Host port reassigned to **3016** (moved off its previous port to free it).
- No ingestion backend wired (see next section), so even when started it cannot
  correctly accept traces.

---

## Why it's blocked: Langfuse v3 backend requirements

Langfuse **v3** is not a single container. Unlike v2 (which could run against
Postgres alone), v3 splits storage across three additional services. All three
must exist and be wired before ingestion works:

| Component | Role in Langfuse v3 | IntegriBilt status |
|---|---|---|
| **ClickHouse** | OLAP store for traces / observations / scores (the high-volume event data) | NOT stood up |
| **Redis** | Async ingestion queue + cache | NOT wired (stack has a Redis; reuse TBD) |
| **Blob / S3-style object storage** | Raw event payload storage (inputs/outputs) | NOT stood up |
| Postgres | Transactional metadata (users, projects, prompts, datasets) | available in stack |

Without ClickHouse + Redis + blob storage, the Langfuse web container will start
but the ingestion pipeline (the "worker") cannot process events.

---

## Bring-up checklist (TODO)

> **TODO (fill in as we learn):** execute and verify each step.

1. **Extend the shared `docker-compose.yml`** (profile `svr02`) with ClickHouse,
   a Redis binding, and blob/object storage (e.g. MinIO or an existing S3
   target). **Never create a separate compose file** — the SVR02 stack is one
   shared `docker-compose.yml`; add services to it.
2. Decide Redis topology: reuse the existing stack Redis vs. a dedicated instance.
   If reusing, mind that **DB index 7 is reserved for agent state** — Langfuse
   must use a different DB index / namespace.
3. Provision a ClickHouse data volume on `/srv` (the OS disk `/` is full; Docker
   data-root already lives on `/srv`, which has free space). Do not place large
   volumes on `/`.
4. Wire the Langfuse web + worker containers to ClickHouse / Redis / blob and the
   existing Postgres; set the Langfuse encryption/salt secrets from **BWS**.
5. Un-park the Langfuse service and confirm the worker drains the ingestion queue.
6. Put it behind the standard reverse proxy / hostname and confirm the OTEL
   endpoint answers at `/api/public/otel`.
7. Smoke-test from the gateway: set `LANGFUSE_OTEL_HOST` to the SVR02 URL, send a
   traced call (see `litellm-gateway-integration.md` §5), confirm it lands.

> **TODO (fill in):** final self-host hostname / reverse-proxy URL for SVR02 Langfuse.
> **TODO (fill in):** BWS secret IDs for Langfuse self-host secrets (encryption key,
> salt, ClickHouse password, blob storage credentials).

---

## Self-host endpoints (once live)

| Use | URL |
|---|---|
| Web UI / API host | `https://<svr02-langfuse-host>` (port 3016 if not fronted by proxy) |
| OTEL ingestion endpoint | `https://<svr02-langfuse-host>/api/public/otel` |
| `LANGFUSE_HOST` (classic callback) | `https://<svr02-langfuse-host>` |
| `LANGFUSE_OTEL_HOST` (otel callback) | `https://<svr02-langfuse-host>` |

Auth for the OTEL endpoint is the same Basic header LiteLLM builds:
`base64("pk-lf-…:sk-lf-…")` — keys from BWS, scoped to the self-host project.

---

## Infrastructure rules that apply here

- One shared `docker-compose.yml` for the SVR02 stack — no extra compose files,
  no standalone `docker run` for managed services.
- Bring the stack up with `./start-stack.sh` or `docker compose --profile svr02 up -d`.
- Recreate DB-backed services (Langfuse, litellm-proxy, postgres) via
  `./start-stack.sh svr02 <service>`, never bare `docker compose up` (the
  `POSTGRES_PASSWORD` parse bug → Prisma `P1000`).
- Use explicit IP `192.168.254.2`, never `localhost`, for cross-host calls.
- Large volumes on `/srv`, not `/` (OS disk is full).
- All secrets via BWS; nothing in cleartext in the repo.
