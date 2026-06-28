# LangChain / LangGraph callback handler

Attach the Langfuse `CallbackHandler` to LangChain or LangGraph invocations and it
traces chains, agents, tools, and retrievers automatically — no manual span code.

Keys from env (BWS). Don't pass literal keys to the handler.

---

## Basic chain

```python
from langchain_openai import ChatOpenAI
from langchain_core.prompts import ChatPromptTemplate
from langfuse.callback import CallbackHandler

langfuse_handler = CallbackHandler(session_id="session-123", user_id="user-456")

llm = ChatOpenAI(model="gpt-4o")
prompt = ChatPromptTemplate.from_messages([
    ("system", "You are a helpful assistant."),
    ("user", "{input}"),
])
chain = prompt | llm

# pass the handler per-invocation
response = chain.invoke(
    {"input": "Hello"},
    config={"callbacks": [langfuse_handler]},
)
```

Set it as a default handler to trace every call without passing config each time:

```python
import langchain
langchain.callbacks.manager.set_handler(langfuse_handler)
response = chain.invoke({"input": "Hello"})   # now traced automatically
```

---

## Agents

The same handler covers agent executors — every LLM step and tool call becomes a
span under the trace.

```python
from langchain.agents import create_openai_tools_agent, AgentExecutor

agent = create_openai_tools_agent(llm, tools, prompt)
agent_executor = AgentExecutor(agent=agent, tools=tools)

result = agent_executor.invoke(
    {"input": "What's the weather?"},
    config={"callbacks": [langfuse_handler]},
)
```

---

## LangGraph

LangGraph honors the same `config={"callbacks": [...]}`. Each node's LLM/tool
activity is traced under one graph run.

```python
result = graph.invoke(
    {"messages": [("user", "Plan and execute this task")]},
    config={"callbacks": [langfuse_handler]},
)
```

For nested graphs/subgraphs, pass the handler at the top-level `invoke`; child
runs inherit it.

---

## Routing LangChain through the IntegriBilt gateway

Point the LangChain LLM at the gateway so calls are also cost-tracked centrally
(and, with the gateway's Langfuse callback on, observed even if you forget the
handler). Use a LiteLLM virtual key from BWS; explicit IP, never `localhost`.

```python
import os
llm = ChatOpenAI(
    model="gpt-4o",
    base_url="http://192.168.254.2:4000",   # IntegriBilt LiteLLM gateway on SVR02
    api_key=os.environ["LITELLM_VIRTUAL_KEY"],  # sourced from BWS
)
```

> If both the gateway callback and the LangChain handler are active, the LLM call
> may be logged twice. Choose one layer for the LLM generation; the handler is
> still useful for the surrounding chain/agent/tool spans the gateway can't see.

---

## Reference workflows

**Observable LangGraph agent**
1. Build the agent with LangGraph.
2. Attach the Langfuse callback handler.
3. Trace all LLM calls and tool uses.
4. Score outputs for quality (see `evaluation-and-datasets.md`).
5. Monitor and iterate.

**Monitored RAG pipeline**
1. Build RAG (retrieval + generation).
2. Trace retrieval spans and the LLM generation.
3. Score relevance and accuracy.
4. Track cost and latency (gateway gives you this for free).
5. Optimize based on the data.

---

Source: consolidated from `awesome-skills/langfuse` (vibeship-spawner-skills,
Apache 2.0).
