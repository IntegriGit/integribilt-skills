# Datasets & evaluations

Promote real traces into datasets, then evaluate. Driven by the `langsmith` CLI command groups `dataset`,
`example`, `evaluator`, and `experiment`. Adapted from
`deepagentsjs/.agents/skills/langsmith-trace/SKILL.md` command tree.

At IntegriBilt the gateway callback already streams production traffic into `litellm-completion`, so evaluation
datasets can be built directly from real usage.

## Build a dataset from real traces

```bash
# 1. Capture golden traces with full inputs/outputs
langsmith trace export ./traces --project litellm-completion --limit 50 --full
cat ./traces/*.jsonl > /tmp/golden.jsonl

# 2. Create the dataset and upload
langsmith dataset create --name regression-set
langsmith dataset upload --name regression-set --file /tmp/golden.jsonl

# 3. Inspect
langsmith dataset list
langsmith dataset get --name regression-set
langsmith example list --dataset regression-set
```

`--full` / `--include-io` on export is **required** — without inputs/outputs the examples are empty.

## Examples

```bash
langsmith example create --dataset regression-set --input '{"question":"..."}' --output '{"answer":"..."}'
langsmith example delete --dataset regression-set --example-id <id>
```

## Evaluators

```bash
langsmith evaluator list
langsmith evaluator upload --file ./evaluators/correctness.json
langsmith evaluator delete --evaluator-id <id>
```

## Experiments (results)

```bash
langsmith experiment list
langsmith experiment get <experiment-id>     # per-evaluator scores for a run over a dataset
```

## Feedback-driven querying

Once evaluators write feedback, slice traces by score with a raw filter:

```bash
langsmith trace list --filter 'and(eq(feedback_key,"correctness"), gte(feedback_score,0.8))'
```

## Workflow summary

1. Production traffic → gateway callback → traces in `litellm-completion`.
2. Export golden traces (`--full`) → dataset.
3. Run experiments against the dataset with evaluators.
4. Inspect experiment scores; filter traces by feedback to find regressions.
5. Add corrected/edge-case rows as examples; re-run.

> **TODO (fill in as we learn):** standardize a small set of IntegriBilt evaluators (e.g. correctness,
> groundedness) and a canonical regression dataset name once an app is in production behind the gateway.
