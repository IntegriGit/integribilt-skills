---
name: langsmith
description: "LangSmith observability for IntegriBilt's lang-family suite. Use when tracing/observing LLM calls in LangSmith, querying or exporting traces, evaluating with datasets, deploying/operating managed deep agents, or wiring LangSmith into the self-hosted LiteLLM gateway (the callback path that traces every model call through http://192.168.254.2:4000). Covers both the gateway-callback route and the LangSmith SDK inside LangChain/LangGraph apps."
---

# LangSmith — IntegriBilt

LangSmith (https://smith.langchain.com) is the observability and evaluation platform for the lang-family
suite. At IntegriBilt there are **two distinct ways traces land in LangSmith**, and you should know which one
applies before you touch anything:

1. **Gateway callback** — the self-hosted **LiteLLM Gateway** (`http://192.168.254.2:4000`, SVR02) emits a
   LangSmith trace for **every model call routed through it**, with zero app changes. This is the primary
   IntegriBilt angle: flip one callback, get fleet-wide LLM observability. See
   [Gateway integration](#litellm-gateway-integration-callback).
2. **SDK / in-app tracing** — LangChain/LangGraph apps trace automatically via env vars; non-framework code uses
   the `traceable` decorator/wrapper. See [SDK / in-app tracing](#sdk--in-app-tracing).

Both routes feed the same LangSmith projects, datasets, and evals. Use the gateway route for breadth (observe
the whole fleet) and the SDK route for depth (nested spans, retrieval steps, custom metadata inside one app).

> Sources: adapted from `deepagentsjs/.agents/skills/langsmith-trace/SKILL.md` (tracing + querying) and
> `langchain-skills/config/skills/managed-deep-agents/SKILL.md` (deploying/operating managed agents), plus
> IntegriBilt LiteLLM→LangSmith facts. Deep material lives in `references/`.

## Secrets (BWS — always)

Never hardcode or write the LangSmith API key in cleartext. Pull it at use time from Bitwarden Secrets Manager:

```bash
export LANGSMITH_API_KEY="$(bws secret get <ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
```

> **TODO (fill in):** BWS secret ID for the LangSmith API key.

A personal-access LangSmith key looks like `lsv2_pt_...`. For org-scoped (service) keys you also set
`LANGSMITH_WORKSPACE_ID`. Redact any key matching `lsv2_` before pasting output into a task log.

## Environment variables

| Variable | Purpose | Default |
| --- | --- | --- |
| `LANGSMITH_API_KEY` | Auth (from BWS, never plaintext) | — (required) |
| `LANGSMITH_PROJECT` | Target project for traces | gateway: `litellm-completion`; SDK: `default` |
| `LANGSMITH_TRACING` | `true` enables SDK/OSS tracing | unset |
| `LANGSMITH_ENDPOINT` | Override API host (self-hosted LangSmith) | `https://api.smith.langchain.com` |
| `LANGSMITH_WORKSPACE_ID` | Org-scoped key workspace | — |
| `LANGSMITH_DEFAULT_RUN_NAME` | Run name for gateway callback traces | `LLMRun` |
| `LANGCHAIN_CALLBACKS_BACKGROUND` | `false` flushes traces before serverless exit (Python) | `true` |

**Always check** `LANGSMITH_PROJECT` (env or `.env`) before querying — it tells you which project holds the
traces you care about. If unset, the gateway writes to `litellm-completion`.

> **TODO (fill in as we learn):** whether IntegriBilt points at LangSmith Cloud (`smith.langchain.com`) or
> stands up self-hosted LangSmith. If self-hosted, set `LANGSMITH_ENDPOINT` fleet-wide and document the host
> here. As of now assume **Cloud**.

---

## LiteLLM gateway integration (callback)

This is the key IntegriBilt path. The LiteLLM gateway can fan every completion out to LangSmith as a callback —
so any app, script, or agent that calls the gateway is observed without importing the LangSmith SDK.

### Proxy (our gateway on SVR02)

The shared gateway config is at `/srv/core/litellm/config.yaml`. Add the `langsmith` callback under
`litellm_settings`:

```yaml
litellm_settings:
  callbacks: ["langsmith"]
```

Provide the env to the proxy container (via the stack's env, sourced from BWS — never inline plaintext):

```bash
LANGSMITH_API_KEY=<from BWS>
LANGSMITH_PROJECT=litellm-completion        # or a per-environment project name
LANGSMITH_DEFAULT_RUN_NAME=LLMRun
```

Restart the proxy the **approved way** — recreate via `start-stack.sh`, never a bare `docker compose up`
(that breaks `POSTGRES_PASSWORD` parsing and DB auth). See the `integribilt-infrastructure` skill and the
LiteLLM restart memory note.

After restart, make one model call through `http://192.168.254.2:4000` and confirm a trace appears in the
`litellm-completion` project at https://smith.langchain.com.

### SDK (standalone LiteLLM, e.g. a local script)

If you embed the LiteLLM Python SDK directly rather than going through the gateway:

```python
import litellm
litellm.callbacks = ["langsmith"]
# env: LANGSMITH_API_KEY, LANGSMITH_PROJECT, LANGSMITH_DEFAULT_RUN_NAME
```

### Batching — make local tests land immediately

LiteLLM batches trace uploads. The batch size defaults to **512**, so during local testing a handful of calls
will *not* show up until the buffer flushes. Set batch size to **1** while testing:

```python
litellm.langsmith_batch_size = 1   # SDK
```

```yaml
litellm_settings:
  callbacks: ["langsmith"]
  langsmith_batch_size: 1          # proxy: testing only — raise back to 512 for production throughput
```

Leave it at the default (or higher) in production for throughput; batch size 1 is a debugging aid only.

More detail, verification steps, and rollback: `references/litellm-gateway.md`.

---

## SDK / in-app tracing

For apps you own the code of. Two cases.

### LangChain / LangGraph (automatic)

Tracing is automatic — just set env and every chain/graph/LLM step is captured:

```bash
export LANGSMITH_TRACING=true
export LANGSMITH_API_KEY="$(bws secret get <ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
export LANGSMITH_PROJECT=my-project
# Point the LLM at the gateway instead of a vendor key:
export OPENAI_API_BASE=http://192.168.254.2:4000
export OPENAI_API_KEY=<gateway virtual key from BWS>
```

In serverless/short-lived processes set `LANGCHAIN_CALLBACKS_BACKGROUND=false` (Python) so traces flush before
exit.

### Non-LangChain code (`traceable` + wrapped client)

Wrap the LLM client and decorate functions you want as spans. Python:

```python
from langsmith import traceable
from langsmith.wrappers import wrap_openai
from openai import OpenAI

# Wrapped client auto-traces every call; base_url points at the IntegriBilt gateway.
client = wrap_openai(OpenAI(base_url="http://192.168.254.2:4000"))

@traceable
def rag_pipeline(question: str) -> str:
    docs = retrieve_docs(question)
    return generate_answer(question, docs)

@traceable(name="retrieve_docs")
def retrieve_docs(query: str) -> list[str]:
    ...
```

TypeScript uses `traceable()` and `wrapOpenAI()` with the same shape. Full Python + TS examples and best
practices: `references/sdk-tracing.md`.

**Gateway vs SDK is not either/or.** A LangGraph app can point its LLM at the gateway (gateway callback traces
the raw model call) *and* run the LangSmith SDK (traces the graph/agent structure). You then see both the
high-level trajectory and the underlying completions.

---

## Querying traces

Query and export with the `langsmith` CLI (language-agnostic). Install:

```bash
curl -sSL https://raw.githubusercontent.com/langchain-ai/langsmith-cli/main/scripts/install.sh | sh
```

**Trace vs run** — a **trace** is the full execution tree (root + all children, one agent invocation); a
**run** is a single node (one LLM or tool call). **Query traces first** — they preserve hierarchy needed for
trajectory analysis and dataset generation.

```bash
# Most common: recent traces in a project
langsmith trace list --limit 10 --project litellm-completion

# Timing/tokens/cost, and time/perf/error filters
langsmith trace list --limit 10 --include-metadata
langsmith trace list --last-n-minutes 60
langsmith trace list --min-latency 5.0 --limit 10     # slow traces (>= 5s)
langsmith trace list --error --last-n-minutes 60      # failed traces

# Full hierarchy for one trace
langsmith trace get <trace-id>

# Export to JSONL (one file per trace, with all runs) — feed datasets/evals
langsmith trace export ./traces --limit 20 --full

# Flat list of a single run type
langsmith run list --run-type llm --limit 20
```

Filters AND together: `--name`, `--tags`, `--min-tokens`, `--since <ISO>`, plus a raw `--filter` for feedback
and metadata, e.g. `--filter 'and(eq(feedback_key,"correctness"), gte(feedback_score,0.8))'`. Full command tree,
filter reference, and export format: `references/querying.md`.

Tips: always pass `--project`; use `/tmp` for temp exports; stitch with `cat ./traces/*.jsonl > all.jsonl`.

---

## Datasets & evaluations

Promote real traces into datasets, then evaluate against them. The same `langsmith` CLI drives it:

```bash
langsmith dataset list
langsmith dataset create --name regression-set
langsmith trace export ./traces --limit 50 --full        # capture golden traces
langsmith dataset upload --name regression-set --file ./traces/all.jsonl
langsmith experiment list
langsmith experiment get <experiment-id>                 # scores per evaluator
```

`example`, `evaluator`, and `experiment` command groups round out the workflow. Because the gateway callback
already streams production traffic into `litellm-completion`, you can build evaluation datasets straight from
real IntegriBilt usage. End-to-end recipe: `references/datasets-and-evals.md`.

---

## Managed deep agents

When LangSmith should **host and operate** an agent (durable threads, streamed runs, managed files, MCP
credential storage), use the Managed Deep Agents runtime. Those agents are traced in LangSmith natively.

```bash
uv tool install "deepagents-cli>=0.2.2"
export LANGSMITH_API_KEY="$(bws secret get <ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
deepagents init research-assistant && cd research-assistant
# edit agent.json (name, description, model "openai:gpt-5.5", backend {"type":"state"}) and AGENTS.md
deepagents deploy --dry-run     # inspect payload + managed file tree first
deepagents deploy
deepagents agents list
```

Use Managed Deep Agents when you want LangSmith to own the runtime; use a **standard LangSmith Deployment**
(`langgraph deploy`) when you need custom routes/auth, the full Agent Server API, stronger isolation, or
self-hosted/Hybrid regions. Python/TS SDKs, React `useStream`, REST fallback, MCP tools, and human-in-the-loop
interrupts are all covered in `references/managed-deep-agents.md`.

> IntegriBilt note: managed agents call the chosen model provider directly via LangSmith, **not** through the
> SVR02 gateway, so the gateway callback does **not** observe them — their observability comes from the managed
> runtime itself. Wire app-level LLM calls through `http://192.168.254.2:4000` only when you control the client.

---

## Troubleshooting

- **No traces appearing (gateway).** Confirm `callbacks: ["langsmith"]` is under `litellm_settings` in
  `/srv/core/litellm/config.yaml`, that `LANGSMITH_API_KEY` reached the container, and that the proxy was
  recreated via `start-stack.sh`. Then check you are looking at the **right project** (`litellm-completion` by
  default, not `default`).
- **Traces delayed in local testing.** Batching. Set `langsmith_batch_size: 1` (proxy) / `litellm.langsmith_batch_size = 1`
  (SDK) so calls land immediately. Revert for production.
- **Traces in the wrong project.** `LANGSMITH_PROJECT` is unset or differs between caller and where you are
  looking. Set it explicitly on the caller and pass `--project` when querying.
- **401 / auth errors.** Key not exported, expired, or org-scoped without `LANGSMITH_WORKSPACE_ID`. Re-pull from
  BWS; never paste the raw key into logs.
- **CLI returns nothing.** No traces match the filters (wrong project/time window) — widen `--last-n-minutes`,
  drop `--error`, confirm `--project`. If a command produced nothing, say so explicitly rather than assuming
  success.
- **LangGraph traces incomplete on exit (serverless).** Set `LANGCHAIN_CALLBACKS_BACKGROUND=false`.
- **Self-hosted LangSmith.** If/when IntegriBilt runs LangSmith on-prem, every component above also needs
  `LANGSMITH_ENDPOINT` pointed at the internal host. See the TODO in [Environment variables](#environment-variables).

---

## References

- `references/litellm-gateway.md` — Gateway callback deep dive: config, batching, restart, verify, rollback.
- `references/sdk-tracing.md` — Full Python + TypeScript `traceable`/`wrap*` examples and best practices.
- `references/querying.md` — Complete `langsmith` CLI command tree, filters, and export format.
- `references/datasets-and-evals.md` — Datasets, examples, evaluators, experiments workflow.
- `references/managed-deep-agents.md` — Deploy/operate managed agents: CLI, SDKs, REST, MCP tools, interrupts.

External: LangSmith UI https://smith.langchain.com · LiteLLM gateway `http://192.168.254.2:4000` (SVR02).
Related IntegriBilt skills: `litellm-skill-manager` (publishing skills *to* the gateway — inverse direction),
`integribilt-infrastructure` (stack/restart procedures, BWS).
