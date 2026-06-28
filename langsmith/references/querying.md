# Querying & exporting traces (`langsmith` CLI)

Adapted from `deepagentsjs/.agents/skills/langsmith-trace/SKILL.md`. The CLI is language-agnostic.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/langchain-ai/langsmith-cli/main/scripts/install.sh | sh
```

Requires `LANGSMITH_API_KEY` (from BWS). **Always check `LANGSMITH_PROJECT`** (env or `.env`) before querying —
it tells you which project holds the relevant traces. At IntegriBilt the gateway writes to `litellm-completion`
by default.

## Trace vs run

- **Trace** = a complete execution tree (root run + all child runs) — one full agent invocation with every LLM
  call, tool call, and nested op.
- **Run** = a single node in the tree (one LLM call, one tool call, etc.).

**Query traces first** — they preserve the hierarchy needed for trajectory analysis and dataset generation.

## Command tree

```
langsmith
├── trace      (operations on trace trees — USE FIRST)
│   ├── list     List traces (filters apply to the root run)
│   ├── get      Get a single trace with full hierarchy
│   └── export   Export traces to JSONL (one file per trace)
├── run        (operations on individual runs — for specific analysis)
│   ├── list     List runs (flat; filters apply to any run; supports --run-type)
│   ├── get      Get a single run
│   └── export   Export runs to a single JSONL file (flat)
├── dataset    list | get | create | delete | export | upload
├── example    list | create | delete
├── evaluator  list | upload | delete
├── experiment list | get
├── thread     list | get
└── project    list
```

### trace vs run differences

| | `trace *` | `run *` |
| --- | --- | --- |
| Filters apply to | Root run only | Any matching run |
| `--run-type` | Not available | Available |
| Returns | Full hierarchy | Flat list |
| Export output | Directory (one file/trace) | Single file |

## Common queries

```bash
# Recent traces in a project (most common)
langsmith trace list --limit 10 --project litellm-completion

# With timing/tokens/cost metadata
langsmith trace list --limit 10 --include-metadata

# Time filters
langsmith trace list --last-n-minutes 60
langsmith trace list --since 2026-06-28T10:00:00Z

# One trace, full hierarchy
langsmith trace get <trace-id>

# Show hierarchy inline while listing
langsmith trace list --limit 5 --show-hierarchy

# Export to JSONL (one file per trace, all runs) for datasets
langsmith trace export ./traces --limit 20 --full

# Performance / errors
langsmith trace list --min-latency 5.0 --limit 10     # slow (>= 5s)
langsmith trace list --error --last-n-minutes 60      # failed

# Flat list of one run type
langsmith run list --run-type llm --limit 20
```

## Filters (AND together)

Basic: `--trace-ids a,b` · `--limit N` · `--project NAME` · `--last-n-minutes N` · `--since ISO` ·
`--error` / `--no-error` · `--name PATTERN` (case-insensitive contains).

Performance: `--min-latency SEC` · `--max-latency SEC` · `--min-tokens N` · `--tags t1,t2` (has any).

Advanced raw query: `--filter QUERY` for feedback/metadata cases, e.g.:

```bash
langsmith trace list --filter 'and(eq(feedback_key, "correctness"), gte(feedback_score, 0.8))'
```

## Export format

`.jsonl`, one run per line:

```json
{"run_id":"...","trace_id":"...","name":"...","run_type":"...","parent_run_id":"...","inputs":{...},"outputs":{...}}
```

Use `--include-io` or `--full` to include inputs/outputs (required for dataset generation).

## Tips

- Start with traces — full context for trajectory and dataset generation.
- `trace export --full` for bulk data destined for datasets.
- Always pass `--project` to avoid mixing data across projects.
- Use `/tmp` for temporary exports.
- `--include-metadata` for performance/cost analysis.
- Stitch files: `cat ./traces/*.jsonl > all.jsonl`.
- If a command returns nothing, the filters matched nothing (wrong project/time window) — say so explicitly.
