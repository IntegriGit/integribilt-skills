# Prompt management

Store prompts in Langfuse, version them, and fetch by **label** at runtime. This
decouples prompt edits from code deploys: edit in the Langfuse UI or via API, move
the `production` label, and running apps pick up the new version on next fetch.

Keys from env (BWS). Never hardcode.

---

## Create / update a prompt

Labels gate which version each environment receives (`production`, `staging`,
`development`). Each `create_prompt` with an existing name makes a new version.

```python
from langfuse import Langfuse
langfuse = Langfuse()

langfuse.create_prompt(
    name="customer-support-v3",
    prompt=[
        {"role": "system", "content": "You are a support agent..."},
        {"role": "user", "content": "{{user_message}}"},
    ],
    config={"model": "gpt-4o", "temperature": 0.7},   # arbitrary config travels with the prompt
    labels=["production"],                              # or ["staging"], ["development"]
)
```

Text prompts (single string) are also supported — pass a string instead of a
message list. `{{variable}}` placeholders are filled by `.compile()`.

---

## Fetch and compile

```python
# Latest version carrying the "production" label
prompt = langfuse.get_prompt("customer-support-v3", label="production")

# Or pin an exact version number
prompt = langfuse.get_prompt("customer-support-v3", version=4)

compiled = prompt.compile(user_message="How do I reset my password?")
# compiled is the ready-to-send message list (or string)

# Config values ride along
model = prompt.config.get("model", "gpt-4o")
temperature = prompt.config.get("temperature", 0.7)

response = openai.chat.completions.create(
    model=model, messages=compiled, temperature=temperature
)
```

---

## Link a prompt version to its generations

Passing `prompt=` to `trace.generation` ties the LLM call to the exact prompt
version, so Langfuse can attribute quality/cost/latency per prompt version — the
backbone of prompt A/B testing.

```python
trace = langfuse.trace(name="support-chat")
generation = trace.generation(
    name="response",
    model="gpt-4o",
    prompt=prompt,         # links to the specific version
)
```

---

## Caching & fallbacks (production hygiene)

- The SDK caches fetched prompts client-side; fetching by label on a hot path is
  cheap. Tune the cache TTL to balance freshness vs. latency.
- Provide a **fallback** prompt so an outage in Langfuse fetch doesn't take the
  app down — keep a hardcoded/last-known prompt to fall back to.
- For the IntegriBilt gateway path, the model/temperature in `prompt.config` can
  drive the request you send to `http://192.168.254.2:4000`.

> **TODO (fill in as we learn):** naming convention for IntegriBilt prompts in
> Langfuse (e.g. `spruce-<feature>-<purpose>`), and which label maps to which
> environment for our apps.

---

Source: consolidated from `awesome-skills/langfuse` (vibeship-spawner-skills,
Apache 2.0).
