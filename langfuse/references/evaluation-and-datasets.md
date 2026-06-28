# Evaluation & datasets

Two layers: **scores** (attach quality/feedback to a trace or observation) and
**datasets** (curated input/expected-output pairs you run an app against to catch
regressions).

Keys from env (BWS).

---

## Scoring traces

```python
from langfuse import Langfuse
langfuse = Langfuse()

trace = langfuse.trace(name="qa-flow")

# numeric (0–1 scale is a common convention)
trace.score(name="relevance", value=0.85, comment="Response addressed the question")

# boolean
trace.score(name="correctness", value=1, data_type="BOOLEAN")
```

Score `data_type` can be `NUMERIC`, `BOOLEAN`, or `CATEGORICAL`. Scores power the
dashboards and let you trend quality over time and per prompt version.

User feedback (thumbs up/down) is just a score with a stable name:

```python
trace.score(name="user-feedback", value=1, comment="User clicked helpful")
```

---

## LLM-as-judge

Use a cheaper model to grade outputs, then write the grade back as a score. Run it
async so it doesn't block the user-facing path.

```python
def evaluate_response(question: str, response: str) -> float:
    eval_prompt = f"""
    Rate the response quality from 0 to 1.

    Question: {question}
    Response: {response}

    Output only a number between 0 and 1.
    """
    result = openai.chat.completions.create(
        model="gpt-4o-mini",                  # cheap judge
        messages=[{"role": "user", "content": eval_prompt}],
    )
    return float(result.choices[0].message.content.strip())

score = evaluate_response(question, response)
trace.score(name="quality-llm-judge", value=score)
```

> At IntegriBilt, route the judge call through the gateway
> (`http://192.168.254.2:4000`) so the eval calls are themselves cost-tracked, and
> pick a cheap model (e.g. a free/`*-mini` route) for the judge.

---

## Datasets — regression evals

Curate input/expected pairs once, then run any app/prompt version against them and
compare scores across runs.

```python
# create the dataset
langfuse.create_dataset(name="support-qa-v1")

# add items
langfuse.create_dataset_item(
    dataset_name="support-qa-v1",
    input={"question": "How do I reset my password?"},
    expected_output="Go to settings > security > reset password",
)

# run an eval pass
dataset = langfuse.get_dataset("support-qa-v1")
for item in dataset.items:
    response = generate_response(item.input["question"])

    trace = langfuse.trace(name="eval-run")
    trace.generation(name="response", input=item.input, output=response)

    similarity = calculate_similarity(response, item.expected_output)
    trace.score(name="similarity", value=similarity)

    item.link(trace, "eval-run-1")   # ties the trace to this dataset item + run name
```

`item.link(trace, "<run-name>")` groups all traces from one pass under a run, so
Langfuse can show aggregate scores per run and diff two prompt versions or models.

---

## Eval loops / CI

Pattern for catching regressions before deploy:

1. Build a dataset of representative inputs + expected outputs (or rubrics).
2. On each candidate prompt/model change, run the dataset, link every trace to its
   item under a named run.
3. Compare aggregate scores (similarity, LLM-judge, correctness) run-to-run.
4. Promote the prompt version (move the `production` label) only if scores hold or
   improve. See `prompt-management.md` for labels.

> **TODO (fill in as we learn):** which IntegriBilt flows get gold datasets
> (e.g. invoice summarization, Spruce front-counter assist) and the scoring rubric
> for each.

---

Source: consolidated from `awesome-skills/langfuse` (vibeship-spawner-skills,
Apache 2.0).
