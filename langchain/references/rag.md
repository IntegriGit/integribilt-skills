# RAG — retrieval-augmented generation

> Built from the official `langchain-rag` skill. At IntegriBilt, **embeddings and
> the LLM both route through the LiteLLM Gateway** — use
> `OpenAIEmbeddings(base_url="http://192.168.254.2:4000", api_key=LITELLM_KEY, model="<gateway-embedding-model>")`
> and a gateway-backed `ChatOpenAI`. Never hit a provider directly.

## Pipeline
1. **Index**: Load → Split → Embed → Store
2. **Retrieve**: Query → Embed → Search → Return docs
3. **Generate**: Docs + Query → LLM → Response

| Vector store | Use case | Persistence |
|--------------|----------|-------------|
| InMemory | Testing | Memory only |
| FAISS | Local, high performance | Disk |
| Chroma | Development | Disk |
| Pinecone | Production, managed | Cloud |

## Complete pipeline

### Python
```python
from langchain_openai import ChatOpenAI, OpenAIEmbeddings
from langchain_community.vectorstores import InMemoryVectorStore
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_core.documents import Document

GATEWAY = "http://192.168.254.2:4000"

docs = [
    Document(page_content="LangChain is a framework for LLM apps.", metadata={}),
    Document(page_content="RAG = Retrieval Augmented Generation.", metadata={}),
]
splitter = RecursiveCharacterTextSplitter(chunk_size=500, chunk_overlap=50)
splits = splitter.split_documents(docs)

embeddings = OpenAIEmbeddings(base_url=GATEWAY, api_key=LITELLM_KEY, model="<gateway-embedding-model>")
vectorstore = InMemoryVectorStore.from_documents(splits, embeddings)
retriever = vectorstore.as_retriever(search_kwargs={"k": 4})

model = ChatOpenAI(base_url=GATEWAY, api_key=LITELLM_KEY, model="<gateway-model>")
query = "What is RAG?"
relevant_docs = retriever.invoke(query)
context = "\n\n".join(d.page_content for d in relevant_docs)
response = model.invoke([
    {"role": "system", "content": f"Use this context:\n\n{context}"},
    {"role": "user", "content": query},
])
```

### TypeScript
```typescript
import { ChatOpenAI, OpenAIEmbeddings } from "@langchain/openai";
import { MemoryVectorStore } from "@langchain/classic/vectorstores/memory";
import { RecursiveCharacterTextSplitter } from "@langchain/textsplitters";
import { Document } from "@langchain/core/documents";

const GATEWAY = "http://192.168.254.2:4000";
const splitter = new RecursiveCharacterTextSplitter({ chunkSize: 500, chunkOverlap: 50 });
const splits = await splitter.splitDocuments(docs);
const embeddings = new OpenAIEmbeddings({ configuration: { baseURL: GATEWAY }, apiKey: process.env.LITELLM_VIRTUAL_KEY, model: "<gateway-embedding-model>" });
const vectorstore = await MemoryVectorStore.fromDocuments(splits, embeddings);
const retriever = vectorstore.asRetriever({ k: 4 });
```

## Document loaders
```python
from langchain_community.document_loaders import PyPDFLoader, WebBaseLoader, DirectoryLoader, TextLoader

pdf = PyPDFLoader("./document.pdf").load()
web = WebBaseLoader("https://docs.langchain.com").load()
dir_docs = DirectoryLoader("path/to/documents", glob="**/*.txt", loader_cls=TextLoader).load()
```
```typescript
import { PDFLoader } from "@langchain/community/document_loaders/fs/pdf";
import { CheerioWebBaseLoader } from "@langchain/community/document_loaders/web/cheerio";
const pdf = await new PDFLoader("./document.pdf").load();
const web = await new CheerioWebBaseLoader("https://docs.langchain.com").load();
```

## Text splitting
```python
from langchain_text_splitters import RecursiveCharacterTextSplitter
splitter = RecursiveCharacterTextSplitter(
    chunk_size=1000,                       # 500–1500 typical
    chunk_overlap=200,                     # 10–20% of chunk size
    separators=["\n\n", "\n", " ", ""],
)
splits = splitter.split_documents(docs)
```

## Vector stores

### Chroma (persistent)
```python
from langchain_chroma import Chroma
vectorstore = Chroma.from_documents(splits, embeddings,
    persist_directory="./chroma_db", collection_name="my-collection")
# Reload
vectorstore = Chroma(persist_directory="./chroma_db",
    embedding_function=embeddings, collection_name="my-collection")
```
```typescript
import { Chroma } from "@langchain/community/vectorstores/chroma";
const vectorstore = await Chroma.fromDocuments(splits, embeddings,
  { collectionName: "my-collection", url: "http://localhost:8000" });
```

### FAISS (save/load)
```python
from langchain_community.vectorstores import FAISS
vectorstore = FAISS.from_documents(splits, embeddings)
vectorstore.save_local("./faiss_index")
loaded = FAISS.load_local("./faiss_index", embeddings, allow_dangerous_deserialization=True)
```

## Retrieval

### Similarity (with scores)
```python
results = vectorstore.similarity_search(query, k=5)
for doc, score in vectorstore.similarity_search_with_score(query, k=5):
    print(score, doc.page_content)
```

### MMR (relevance + diversity)
```python
retriever = vectorstore.as_retriever(
    search_type="mmr",
    search_kwargs={"fetch_k": 20, "lambda_mult": 0.5, "k": 5},
)
```

### Metadata filtering
```python
docs = [Document(page_content="Python guide", metadata={"language": "python", "topic": "programming"})]
results = vectorstore.similarity_search("programming", k=5, filter={"language": "python"})
```

## RAG as an agent tool
```python
from langchain.agents import create_agent
from langchain.tools import tool

@tool
def search_docs(query: str) -> str:
    """Search documentation for relevant information."""
    return "\n\n".join(d.page_content for d in retriever.invoke(query))

agent = create_agent(model=llm, tools=[search_docs])
```

## Boundaries
**Can configure:** chunk size/overlap, embedding model, k, metadata filters, search algorithm (similarity / MMR).
**Cannot:** change embedding dimensions (fixed per model); mix embeddings from different models in one store.

## Common fixes
```python
# Chunk size — not too small (loses context), not too large (hits limits)
# WRONG: chunk_size=50  /  chunk_size=10000
# CORRECT:
RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)

# Overlap — keep context across boundaries (10–20%)
# WRONG: chunk_overlap=0  →  CORRECT: chunk_overlap=200

# Persistence — don't lose the index on restart
# WRONG: InMemoryVectorStore.from_documents(...)
# CORRECT: Chroma.from_documents(docs, embeddings, persist_directory="./chroma_db")

# Consistent embeddings — same model for index AND query
embeddings = OpenAIEmbeddings(base_url=GATEWAY, api_key=LITELLM_KEY, model="<gateway-embedding-model>")
vectorstore = Chroma.from_documents(docs, embeddings)
retriever = vectorstore.as_retriever()   # reuses the same embeddings

# FAISS deserialization
loaded = FAISS.load_local("./faiss_index", embeddings, allow_dangerous_deserialization=True)

# Dimension mismatch — index dim must equal embedding dim (don't mix 512 vs 1536)
```
