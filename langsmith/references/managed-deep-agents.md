# Managed Deep Agents (deploy & operate in LangSmith)

Adapted from `langchain-skills/config/skills/managed-deep-agents/SKILL.md`. Managed Deep Agents is a **hosted
runtime** in LangSmith for creating, running, and operating Deep Agents: a versioned Context Hub agent repo,
durable threads, streamed runs, MCP credential storage, managed files, and optional LangSmith sandboxes.

Use this path when the user wants **LangSmith to host and operate** the agent. For self-hosted deployments,
custom routes, or the full Agent Server API surface, use a standard LangSmith Deployment (`langgraph deploy`).

> IntegriBilt note: managed agents call the model provider via LangSmith, **not** through the SVR02 LiteLLM
> gateway — so the gateway `langsmith` callback does not observe them. Their observability comes from the
> managed runtime itself.

## When to use

- Deploy a managed agent from local project files.
- Create/update one from Python, TypeScript, or REST.
- Run an agent on a durable thread and stream output.
- Build a React chat UI with `@langchain/react` `useStream`.
- Register MCP servers, list MCP tools, configure tool interrupts.

## Prerequisites

- Managed Deep Agents preview access in the target workspace.
- LangSmith API key (from BWS).
- A client:

```bash
uv tool install "deepagents-cli>=0.2.2"
pip install managed-deepagents
npm install @langchain/managed-deepagents @langchain/react
```

```bash
export LANGSMITH_API_KEY="$(bws secret get <ID> -t "$BWS_ACCESS_TOKEN" | jq -r .value)"
```

SDKs default to `https://api.smith.langchain.com/v1/deepagents`. Override with `LANGSMITH_ENDPOINT` or
`api_url`/`apiUrl`. For REST set `DEEPAGENTS_BASE_URL="https://api.smith.langchain.com/v1/deepagents"`; all REST
requests auth with header `X-Api-Key: <LANGSMITH_API_KEY>`. **Never ship a long-lived key to browser code** —
proxy through your own backend.

## Choose an interface

| Interface | Use for |
| --- | --- |
| `deepagents-cli>=0.2.2` | Normal project-file workflow: scaffold, edit, deploy, manage MCP servers. |
| Python SDK `managed-deepagents` | Server-side automation, tests, scripts, streaming. |
| TS SDK `@langchain/managed-deepagents` | Server-side TS automation, LangGraph-compatible streaming. |
| React `useStream` | Chat UIs that let LangGraph own thread/run/projection state. |
| REST `/v1/deepagents` | Low-level fallback when a client lacks a field. |

## Project file tree

```text
my-agent/
  agent.json                 # name, description, model, backend, permissions, optional target agent_id
  AGENTS.md                  # main agent instructions
  tools.json                 # MCP-backed tools + interrupt_config
  skills/<name>/SKILL.md     # reusable instructions/files the agent can load
  subagents/<name>/agent.json
  subagents/<name>/AGENTS.md
  subagents/<name>/tools.json
```

## Backends

Use `state` unless sandbox behavior is needed:

```json
{ "backend": { "type": "state" } }
```

Use `sandbox` for code execution / filesystem / long-running work (`scope` must be `thread` or `agent`):

```json
{
  "backend": {
    "type": "sandbox",
    "sandbox_config": {
      "scope": "thread",
      "policy_ids": ["policy-id"],
      "idle_ttl_seconds": 900,
      "delete_after_stop_seconds": 300
    }
  }
}
```

## CLI workflow

```bash
deepagents init research-assistant && cd research-assistant
# edit agent.json:
#   "model": "openai:gpt-5.5", "backend": {"type": "state"}
# edit AGENTS.md
deepagents deploy --dry-run        # print payload + managed file tree, no deploy
deepagents deploy
```

| Command | Use |
| --- | --- |
| `deepagents --version` | Confirm `>=0.2.2`. |
| `deepagents agents list` | List agents in the workspace. |
| `deepagents agents get <id> --include-files` | Inspect an agent + managed files. |
| `deepagents mcp-servers add --url URL --name NAME` | Register a static-header MCP server. |
| `deepagents mcp-servers add --url URL --auth-type oauth --connect` | Register + connect an OAuth MCP server. |
| `deepagents mcp-servers tools <id\|name\|url>` | List tools, print paste-ready `tools.json` snippet. |
| `deepagents mcp-servers connect <id\|name\|url>` | Complete OAuth for a registered server. |

For shared repos, put the target `agent_id` in `agent.json`; the CLI confirms before updating that remote agent.
Use `--yes` only when the target is intentional.

## MCP tools

```json
{
  "tools": [
    {
      "name": "read_url_content",
      "mcp_server_url": "https://example.com/mcp",
      "mcp_server_name": "my-tools",
      "display_name": "read_url_content"
    }
  ],
  "interrupt_config": {
    "https://example.com/mcp::read_url_content": false
  }
}
```

- `mcp_server_url` must match a registered workspace MCP server URL.
- `tools[].name` is the **tool name exposed by the MCP server**, not the server display name.
- List tools first (`deepagents mcp-servers tools <server>` or SDK `list_tools`) to avoid name mismatches.
- `interrupt_config` keys are `{mcp_server_url}::{tool_name}`; set `true` to require human approval before the
  tool runs.

Python tool listing:

```python
from managed_deepagents import Client
with Client() as client:
    tools = client.mcp_servers.list_tools(url="https://example.com/mcp", force_refresh=True)
    print(tools["tools"])
```

## Python SDK workflow

```python
from managed_deepagents import Client

with Client() as client:
    agent = client.agents.create(
        name="research-assistant",
        description="Research assistant that can search the web and summarize sources.",
        model="openai:gpt-5.5",
        backend={"type": "state"},
        instructions="You are a careful research assistant. Search, keep notes, cite sources.",
    )
    thread = client.threads.create(
        agent_id=agent["id"],
        options={"test_run": False, "skip_memory_write_protection": False},
    )
    for event in client.threads.stream(
        thread["id"], agent_id=agent["id"],
        messages=[{"role": "user", "content": "Summarize recent agent-memory approaches."}],
        stream_mode=["values", "updates", "messages-tuple"],
        stream_subgraphs=True,
        user_timezone="America/Los_Angeles",
    ):
        print(event.event, event.data)
```

Async clients: `AsyncClient` with matching resource names.

## TypeScript SDK workflow

```ts
import { Client } from "@langchain/managed-deepagents";

const client = new Client({ apiKey: process.env.LANGSMITH_API_KEY });
const agent = await client.agents.create({
  name: "research-assistant",
  description: "Research assistant that can search the web and summarize sources.",
  model: "openai:gpt-5.5",
  backend: { type: "state" },
  instructions: "You are a careful research assistant. Search, keep notes, cite sources.",
});
const thread = await client.threads.create({
  agent_id: agent.id,
  options: { test_run: false, skip_memory_write_protection: false },
});
const lg = client.getLangGraphClient({ agentId: agent.id });
const stream = lg.runs.stream(thread.id, agent.id, {
  input: { messages: [{ role: "user", content: "Summarize recent agent-memory approaches." }] },
  streamMode: ["values", "updates", "messages-tuple"],
  streamSubgraphs: true,
});
for await (const event of stream) console.log(event.event, event.data);
```

## React `useStream`

```tsx
import { Client } from "@langchain/managed-deepagents";
import { useStream } from "@langchain/react";

const agentId = "<agent_id>";
const managed = new Client({ apiKey: process.env.LANGSMITH_API_KEY }); // server-only / proxy; never browser key
const client = managed.getLangGraphClient({ agentId });

export function ManagedDeepAgentStream() {
  const stream = useStream({ client, assistantId: agentId, fetchStateHistory: false });
  return (
    <button disabled={stream.isLoading}
      onClick={() => void stream.submit({ messages: [{ role: "user", content: "Write a status update." }] })}>
      Run agent
    </button>
  );
}
```

`stream.submit({ messages })` is the UI-level shape; the adapter rewrites it to the stream route as
`input.messages`.

## REST fallback

`POST {BASE_URL}/agents`, `POST {BASE_URL}/threads`, then stream:

```python
import os, httpx
BASE_URL = os.environ["DEEPAGENTS_BASE_URL"]
HEADERS = {"X-Api-Key": os.environ["LANGSMITH_API_KEY"]}

payload = {
    "agent_id": agent_id,
    "input": {"messages": [{"role": "user", "content": "Summarize agent-memory tradeoffs."}]},
    "stream_mode": ["values", "updates", "messages-tuple"],
    "stream_subgraphs": True,
}
with httpx.stream("POST", f"{BASE_URL}/threads/{thread_id}/runs/stream",
                  headers={**HEADERS, "Accept": "text/event-stream"},
                  json=payload, timeout=None) as r:
    r.raise_for_status()
    for line in r.iter_lines():
        if line:
            print(line)
```

REST stream payloads use `input.messages` (SDK helpers accept `messages` and normalize). Set
`Accept: text/event-stream`. `stream_subgraphs: true` emits subagent events too.

## Human-in-the-loop interrupts

When `interrupt_config` flags a tool `true`, the run pauses before the tool and emits `__interrupt__` inside a
`values`/`updates` event, then the stream closes. Resume with a follow-up run carrying `command.resume`:

```python
client.threads.stream(
    thread_id, agent_id=agent_id,
    messages=[{"role": "system", "content": ""}],     # non-empty no-op message required
    command={"resume": {"decisions": [{"type": "approve"}]}},
    stream_mode=["values", "updates", "messages-tuple"],
    stream_subgraphs=True,
)
```

| Decision | Shape | Effect |
| --- | --- | --- |
| Approve | `{"type":"approve"}` | Run the tool with proposed args. |
| Edit | `{"type":"edit","edited_action":{"name":"...","args":{...}}}` | Run with modified name/args. |
| Reject | `{"type":"reject","message":"..."}` | Block; return error ToolMessage to the model. |
| Respond | `{"type":"respond","message":"..."}` | Skip the tool; return synthetic success reply. |

Send exactly one decision per `action_request`, in order; each `type` must be in the matching
`review_configs[i].allowed_decisions`. The resume value is the object `{"decisions":[...]}`, **not** a bare list.

`POST /v1/deepagents/threads/{thread_id}/resolve-interrupt` (no body, returns 204) **terminates** the paused
run at the interrupt — it is **not** an approve shortcut.

## When NOT to use Managed Deep Agents

Use a standard LangSmith Deployment (`langgraph deploy`) when you need: custom app code/routes; advanced auth
around your own server; the full Agent Server API; stronger isolation / max scalability; a region other than
supported Cloud regions, or self-hosted/Hybrid.

## Gotchas

- Use `deepagents-cli>=0.2.2` (older versions emit stale backend names).
- Use canonical backends: `state`, or `sandbox` with `sandbox_config.scope`.
- REST stream payloads use `input.messages`.
- Never ship API keys to browsers — proxy or custom `fetch`.
- `PATCH` can replace nested fields wholesale — pass the full desired tool set when updating tools.
- `tools[].name` must match the MCP tool name or the model never sees the tool.
- Resume with `command.resume = {"decisions":[...]}`; resume runs still need a non-empty message list.
- `resolve-interrupt` cancels/finalizes — it does not approve.
- Model IDs include the provider prefix: `openai:gpt-5.5`, not a bare name.
- MCP credentials are sensitive — never log headers or raw credential payloads.
- Deleting an agent does **not** delete its threads — clean those up explicitly.
- `/v1/deepagents` is still evolving — prefer SDK/CLI surfaces for user-facing workflows.
