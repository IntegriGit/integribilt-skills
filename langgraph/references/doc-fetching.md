# Live LangGraph documentation fetching

Built from `deepagentsjs/langgraph-docs`. Use when a LangGraph question needs current, authoritative answers beyond this skill.

## Workflow

1. **Fetch the index.** Read `https://docs.langchain.com/llms.txt` — a structured list of all docs with descriptions.
2. **Select 2–4 relevant URLs** from the index, prioritizing:
   - specific how-to guides for implementation questions
   - core concept pages for understanding questions
   - tutorials for end-to-end examples
   - reference docs for API details
3. **Fetch the selected URLs.**
4. **Answer using what you read**, not memory — APIs change.

## IntegriBilt note

Per IntegriBilt doctrine, use the `/browse` gstack skill for web browsing rather than ad-hoc browser MCP tools. For plain text fetches (like `llms.txt` and doc pages), `WebFetch` is fine. Cite the doc URLs you used so the answer is auditable.
