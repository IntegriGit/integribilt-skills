# Langtrace, OTEL, and the lang-family comparison (reference)

> Generic OTEL concepts here are drawn from the toolbox skills
> `awesome-skills/distributed-tracing` and `awesome-skills/observability-engineer`.
> Apply them as **mental model**; keep Langtrace-specific claims grounded in
> https://langtrace.ai, not inferred from Jaeger/Tempo.

## OTEL model applied to LLM apps

Langtrace is OpenTelemetry-native. The same trace model used for microservice
tracing maps directly onto LLM/agent runs:

- **Trace** — one end-to-end request or agent run (a single user turn, a chain
  execution).
- **Span** — one operation within the trace. For LLM apps the common span kinds
  are: LLM call, tool/function call, retrieval (vector search), and the
  chain/agent span that parents them. Spans nest:

  ```
  Trace (agent run)
    └─ Span: agent / chain
         ├─ Span: retrieval (vector search)
         ├─ Span: LLM call (model=gpt-4o-mini)  [latency, tokens, cost]
         └─ Span: tool call (function=lookup_invoice)
  ```

- **Attributes (tags)** — key/value pairs on a span used for filtering and
  analysis. LLM observability platforms follow the OTEL **GenAI semantic
  conventions** (the `gen_ai.*` namespace): system/provider, request model,
  response model, prompt and completion content, and token usage. That is how
  model name, prompt/response, token counts, latency, and cost end up queryable
  per span.
- **Context propagation** — the trace/span context threads through nested calls
  so child spans attach to the right parent. In a single-process LLM app this is
  automatic; across services it rides OTEL context headers (see
  `distributed-tracing`).
- **Sampling** — OTEL sampling applies. For LLM tracing, full capture is common
  during development; sample in high-volume production to control cost/overhead
  (generic guidance — confirm Langtrace's own sampling controls in its docs).

> **TODO (fill in as we learn):** the exact `gen_ai.*` (or Langtrace-specific)
> attribute keys Langtrace emits per LLM span, and which providers/models get
> full token+cost capture through the LiteLLM callback.

## Comparison: Langtrace vs. Langfuse-OTEL vs. LangSmith

All three attach to LiteLLM as a callback and observe LLM calls; they differ in
backend and native data model.

| Aspect | **Langtrace** | **Langfuse** | **LangSmith** |
|---|---|---|---|
| LiteLLM callback | `callbacks: ["langtrace"]` | `callbacks: ["langfuse"]` | `callbacks: ["langsmith"]` |
| Native data model | **OTEL spans, end to end** | Langfuse trace/observation model; **also** accepts OTEL/OTLP ingestion | LangSmith run tree; OTEL export available |
| Standards posture | OTEL-first | Hybrid (own model + OTEL) | Own model + OTEL bridge |
| Self-host | Self-hostable (IntegriBilt deploy = **TODO**, see SKILL.md) | Self-hostable | Primarily SaaS (self-host enterprise) |
| IntegriBilt skill | this skill (`langtrace`) | `langfuse` *(planned — not yet authored)* | `langsmith` *(planned — not yet authored)* |

### When to reach for which (rule of thumb)

- **Langtrace** — when you want OTEL-native tracing that interoperates with any
  OTEL collector/backend, and a clean span model for LLM + tool + retrieval.
- **Langfuse** — when you also want prompt management, evals, and a
  trace+observation model, with an OTEL ingestion option if needed.
- **LangSmith** — when the app is LangChain/LangGraph-centric and you want the
  tightest integration with that ecosystem's run tree.

> These are general distinctions. IntegriBilt has not finalized which backend(s)
> are standard for which workload — treat this as orientation, not policy.

## Cross-links

- `awesome-skills/distributed-tracing` — trace/span/context/sampling fundamentals.
- `awesome-skills/observability-engineer` — broader observability practice.
- `litellm-skill-manager` (integribilt-skills) — names the same lang-family suite
  (langfuse / langsmith / langtrace / langchain-langgraph); the inverse direction
  (publishing skills *to* the gateway).
- `integribilt-infrastructure` — SVR02 stack, shared compose, BWS, restart method.

> **NOTE:** `langfuse` and `langsmith` skills are **forward references** — they
> are part of the planned suite but not yet authored in `integribilt-skills/`.
> Repoint these links to real paths once those skills exist.
