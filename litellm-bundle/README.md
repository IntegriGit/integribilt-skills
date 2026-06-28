# litellm-bundle

The IntegriBilt **LiteLLM / lang-family** skill bundle — the complete skill set for the 1–2 dedicated employees whose only job is operating the LiteLLM gateway observability + lang-family stack.

This bundle does **not** duplicate the skills. The skills are canonical in their own dirs under `integribilt-skills/`; this folder is the **manifest + installer** that groups them and pushes them into Paperclip (and, separately, into the LiteLLM gateway marketplace).

## What's in the bundle

| Skill | Purpose |
|---|---|
| `langfuse` | Langfuse observability — self-host + LiteLLM callback/OTEL, tracing, prompts, evals |
| `langsmith` | LangSmith tracing — via the LiteLLM gateway callback and the SDK |
| `langtrace` | Langtrace (OTEL) observability — LiteLLM callback (early/partial) |
| `langgraph` | LangGraph stateful agents — fundamentals, persistence, HITL, CLI, against the gateway |
| `langchain` | LangChain — agents, tools, middleware, RAG, against the gateway |
| `litellm-skill-manager` | Publish/enable/audit skills on the LiteLLM gateway marketplace |

All six bake in the IntegriBilt LiteLLM gateway (`http://192.168.254.2:4000`) and BWS-only secrets. Open items are flagged in-skill as `TODO (fill in as we learn)` — the recurring one is the BWS secret IDs.

## Install into Paperclip

Prereq: the skills must be reachable by Paperclip's importer. Preferred source is the GitHub repo (`IntegriGit/integribilt-skills`); local-path import works for dev. See `install-into-paperclip.sh`.

```bash
# operator env (get these from your Paperclip instance / paperclipai CLI):
export PAPERCLIP_API_URL="http://localhost:3100"
export PAPERCLIP_COMPANY_ID="<company-id>"
export PAPERCLIP_API_KEY="<operator/board token>"
# optionally, the dedicated employee agent id(s):
export PAPERCLIP_AGENT_IDS="<agent-id-1> <agent-id-2>"

bash install-into-paperclip.sh
```

The script imports each skill into the company library, verifies it, and (if `PAPERCLIP_AGENT_IDS` is set) assigns the whole bundle to those employees via `skills/sync`.

## Also: load into the LiteLLM gateway marketplace

Separately from Paperclip, these get published to the gateway via the `litellm-skill-manager` skill (push to `IntegriGit/integribilt-skills`, then register+enable). See that skill's SKILL.md.

> **TODO (fill in as we learn):** the Paperclip `company-id` and operator token (or the `paperclipai` CLI invocation) so the install can run unattended; and confirm whether Paperclip should import by GitHub repo ref or local path in this environment.
