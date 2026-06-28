# langgraph CLI reference

Built from `langgraph-cli`. All commands except `new` read `langgraph.json`.

## Install

```bash
# Python
pip install 'langgraph-cli[inmem]'    # includes `langgraph dev`
pip install langgraph-cli              # build/up/deploy only
uv add "langgraph-cli[inmem]"          # uv equivalent

# JavaScript
npx @langchain/langgraph-cli            # on demand
npm install -g @langchain/langgraph-cli # global -> `langgraphjs`
```

## Commands

### `langgraph new [PATH]`
```bash
langgraph new                          # interactive template select
langgraph new ./my-agent
langgraph new --template agent-python
```
Templates: `deep-agent-python`, `deep-agent-js`, `agent-python`, `new-langgraph-project-python`, `new-langgraph-project-js`.

### `langgraph dev` — local hot-reload, no Docker (port 2024)
```bash
langgraph dev
langgraph dev --port 8000
langgraph dev --no-reload
langgraph dev --no-browser
langgraph dev --host 0.0.0.0           # trusted networks only
langgraph dev --tunnel                 # Cloudflare tunnel for remote access
langgraph dev --debug-port 5678        # remote debugger (needs debugpy)
```

### `langgraph build` — Docker image
```bash
langgraph build -t my-image
langgraph build -t my-image --no-pull
langgraph build -t my-image --base-image langchain/langgraph-server:0.2.18
```

### `langgraph up` — Docker Compose stack incl. Postgres (port 8123)
```bash
langgraph up
langgraph up --port 8000
langgraph up --watch                   # restart on file changes
langgraph up --recreate                # fresh build (pre-deploy validation)
langgraph up --postgres-uri postgresql://...
langgraph up --image my-image          # skip build
langgraph up -d docker-compose.yml     # extra services
langgraph up --wait                    # block until healthy
```

### `langgraph deploy` — LangGraph Platform (LangSmith Deployments). Needs Docker.
```bash
langgraph deploy --name my-agent
langgraph deploy --deployment-type prod
langgraph deploy --tag v1.2.0
langgraph deploy --deployment-id <id>  # update existing
langgraph deploy --no-wait
```
Prereq: `LANGSMITH_API_KEY` in env or `.env`. On Apple Silicon, Docker Buildx is required (cross-compile to linux/amd64).

```bash
langgraph deploy list --name-contains bot
langgraph deploy delete <id> --force
langgraph deploy logs -f                       # follow runtime logs
langgraph deploy logs --type build
langgraph deploy logs --level error -q "timeout" --limit 500
```

### `langgraph dockerfile <SAVE_PATH>`
```bash
langgraph dockerfile ./Dockerfile
langgraph dockerfile ./Dockerfile --add-docker-compose   # also compose + .env + .dockerignore
```

## `langgraph.json`

```json
{
  "dependencies": [".", "langchain_openai", "./local_package"],
  "graphs": {
    "agent": "./my_agent/agent.py:graph",
    "retriever": "./my_agent/rag.py:rag_graph"
  },
  "env": "./.env",
  "python_version": "3.12",
  "dockerfile_lines": ["RUN apt-get update && apt-get install -y ffmpeg"]
}
```

| Key | Required | Description |
|-----|----------|-------------|
| `dependencies` | Yes | `"."` resolves local package config (`pyproject.toml`/`requirements.txt`/`package.json`); also subdir paths or package names |
| `graphs` | Yes | `id -> ./file.py:variable` (Py) or `./file.js:function` (JS); must be a CompiledGraph or a factory returning one |
| `env` | No | path to `.env` (string) or inline name→value object; `deploy` uploads these as secrets |
| `python_version` | No | `3.11`/`3.12`/`3.13` (default 3.11) |
| `node_version` | No | Node version for JS projects |
| `pip_config_file` | No | custom package index config |
| `dockerfile_lines` | No | extra Dockerfile lines after base image |

## `dev` vs `up`

| | `langgraph dev` | `langgraph up` |
|--|-----------------|----------------|
| Docker | No | Yes |
| Use | rapid dev/test | production-like validation |
| State | in-memory/pickled | PostgreSQL |
| Hot reload | yes (default) | optional (`--watch`) |
| Port | 2024 | 8123 |

## Typical workflow

1. `langgraph new` — scaffold.
2. Edit `langgraph.json` — deps, point `graphs` at compiled graph, add `.env`.
3. `langgraph dev` — iterate.
4. `langgraph up --recreate` — validate in Docker + Postgres.
5. `langgraph deploy` — ship (LangGraph Platform).
6. `langgraph deploy logs -f` — monitor.

## IntegriBilt notes

- Prefer `langgraph up` on the shared SVR02 Docker stack for self-hosted runs — keeps state on SVR02 Postgres, stays on-network. `langgraph deploy` ships off-network to LangGraph Platform; use deliberately.
- Populate `.env` (`LITELLM_API_KEY`, `DATABASE_URL`, tracing keys) from BWS at deploy time. Never commit secrets.
- > **TODO (fill in as we learn):** standardize on `langgraph up` vs LangGraph Platform, and the compose profile for LangGraph services in the shared `docker-compose.yml`.

## Gotchas

- `langgraph deploy` only updates deployments **it** created — UI/GitHub-created ones must be managed in the UI.
- `langgraph dev` runs without Docker — system deps (e.g. `ffmpeg`) must be installed locally; use `up` to validate Docker builds.
- `dependencies` must point to where package config lives (e.g. `"."`).
- JS: `npx @langchain/langgraph-cli <cmd>` or `langgraphjs` if globally installed.
- `LANGSMITH_API_KEY` required for `deploy`; optional for `dev` (no traces without it). Also accepted as `LANGGRAPH_HOST_API_KEY` / `LANGCHAIN_API_KEY`.
