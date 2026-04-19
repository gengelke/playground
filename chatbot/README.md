# Local-first Chatbot

This is a simple Python 3.12 chatbot component for the DevOps playground. It can
run by itself, or it can be added to a larger docker-compose setup and connected
to other services through configuration.

The same internal chat logic is used by:

- CLI: `python -m app.cli ...`
- REST API: `POST /api/chat`
- Web UI: `GET /`

The code deliberately avoids agent frameworks, dependency injection frameworks,
abstract base classes, factories, and hidden wiring.

## Request Pipeline

Every request goes through `app/chat.py` in this order:

1. Normalize user input.
2. Check exact configured rules.
3. Check regex rules.
4. Check whitelisted configured commands.
5. Check configured local file, SQLite, and REST knowledge sources.
6. Check local document chunks stored in SQLite.
7. Check Qdrant semantic retrieval when RAG is enabled.
8. Optionally check web search.
9. Call the selected LLM only when needed.

The response includes `source`, `provider`, `model`, `tool`, and `metadata` so
callers can see where the answer came from.

## Project Structure

```text
chatbot/
  app/
    chat.py          central request pipeline
    cli.py           CLI interface
    config.py        YAML/env config loading
    ingest.py        document ingestion
    llm.py           local, OpenAI, Anthropic calls
    main.py          FastAPI app
    models.py        small dataclasses
    retrieval.py     SQLite and Qdrant retrieval
    sources.py       rules, tools, files, REST, SQLite, web search
    static/index.html
  config/config.yml
  sample_docs/devops-playground.md
  tests/
  Dockerfile
  docker-compose.yml
  requirements.txt
```

## Local Setup

Using the Makefile:

```bash
cd chatbot
make run MODE=bare
```

That creates `.venv`, installs `requirements.txt`, starts the sibling `ollama`
service, pulls `llama3.1` if needed, and starts uvicorn in the foreground.
Ollama model data is preserved on the host under `ollama/data`.

To run the chatbot in the background instead:

```bash
make up MODE=bare
make logs MODE=bare
make down MODE=bare
```

Manual equivalent:

```bash
cd chatbot
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

For the local LLM path, also start Ollama:

```bash
make -C ../ollama up MODE=docker
```

Run the API:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8088
```

Open:

```text
http://localhost:8088
```

Health check:

```bash
curl -s http://localhost:8088/health
```

## CLI Usage

Exact deterministic rule:

```bash
python -m app.cli ask "How are you?"
```

Whitelisted command:

```bash
python -m app.cli ask "local time"
```

Interactive mode:

```bash
python -m app.cli shell
```

Select a provider and model:

```bash
python -m app.cli ask "Explain these Jenkins notes" --provider openai --model gpt-4.1-mini --force-llm
python -m app.cli ask "Explain these Jenkins notes" --provider anthropic --model claude-3-5-sonnet-latest --force-llm
python -m app.cli ask "Explain these Jenkins notes" --provider local --model llama3.1 --force-llm
```

If no provider or model is supplied, `config/config.yml` decides.

## REST Usage

```bash
curl -s http://localhost:8088/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"How are you?"}' | jq
```

With strict RAG and provider override:

```bash
curl -s http://localhost:8088/api/chat \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Explain what the playground note says about Jenkins",
    "provider": "local",
    "model": "llama3.1",
    "use_rag": true,
    "force_llm": true
  }' | jq
```

With `use_rag`, the chatbot retrieves RAG context from SQLite/Qdrant. If context
is found, the selected LLM answers using only that retrieved context. If no
relevant context is found, the response source is `rag_empty` and no LLM provider
is called. The older `rag_only` request field is still accepted for compatibility
and has the same strict-RAG behavior.

For local-file-only answers, use `use_local_files` and do not set `use_rag`:

```bash
curl -s http://localhost:8088/api/chat \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "faq services",
    "use_rag": false,
    "use_local_files": true
  }' | jq
```

`use_rag` and `use_local_files` are mutually exclusive.

## Ingestion Flow

Ingestion stores chunks in SQLite and, when Qdrant is enabled and reachable,
also stores vectors in Qdrant. The embedding is deterministic and local, so
ingestion works without OpenAI, Anthropic, or a local LLM.

SQLite and Qdrant retrieval have simple relevance gates in `config/config.yml`:
`min_query_chars`, `min_query_tokens`, and `min_score`. This prevents very short
or unrelated questions from always returning stored chunks. The `use_rag` flag
controls whether document chunks are added to LLM context. Raw chunks are only
returned as a fallback if the selected LLM is unavailable.

```bash
python -m app.cli ingest sample_docs --reset
python -m app.cli ask "Jenkins REST API playground note"
```

PDFs can be ingested from the CLI the same way. The PDF is prepared into
Markdown first, then the prepared Markdown is stored and indexed:

```bash
python -m app.cli ingest ~/Documents/example-ebook.pdf --reset
```

The sample documents include `sample_docs/playground-faq.md`, a detailed FAQ
generated from the top-level playground README. It explains the playground,
service roles, orchestration commands, per-service commands, central port
configuration, chatbot usage, and how the services relate to each other. It can
be used as a configured local file or ingested into SQLite/Qdrant RAG with the
same `sample_docs` command.

The API also exposes ingestion:

```bash
curl -s http://localhost:8088/api/ingest \
  -H 'Content-Type: application/json' \
  -d '{"paths":["sample_docs"],"reset":true}' | jq
```

Programmatic browser-style uploads use multipart form data:

```bash
curl -s http://localhost:8088/api/ingest/files \
  -F reset=false \
  -F 'files=@/path/to/example-ebook.pdf;type=application/pdf' | jq
```

The web UI at `http://localhost:8088/` also has an ingestion form. Enter one
server-visible path per line, for example `sample_docs`. In Docker mode, paths
must exist inside the chatbot container or be mounted into it. The same form can
also upload files selected in the browser. Uploaded files are stored under
`data/uploads` inside the chatbot service and then ingested into SQLite/Qdrant.
PDF uploads are extracted, cleaned, converted to Markdown under
`data/uploads/prepared`, and then ingested from that prepared text.

Supported document inputs are text-like files (`.txt`, `.md`, `.json`, `.yaml`,
`.csv`, `.html`, logs), simple `.epub` text extraction, and `.pdf` preparation
through `pypdf`. The PDF path removes repeated header/footer lines, page number
lines, fixes common hyphenated line breaks, normalizes paragraphs, writes
Markdown sections, and ingests those sections. Temporary/editor files such as
`.swp`, `.un~`, `.bak`, and files ending in `~` are skipped so stale editor
state does not become RAG context.

## Document Chunks

A chunk is one small piece of an ingested document. The chatbot does not pass
whole files to the LLM when RAG is enabled. Instead, ingestion reads a document,
normalizes its text, splits it into chunks, stores those chunks in SQLite, and
also stores one vector per chunk in Qdrant when Qdrant is enabled.

The current defaults are configured in `config/config.yml`:

```yaml
documents:
  chunk_size: 900
  chunk_overlap: 150
  top_k: 4
```

That means a normal document is split into roughly 900-character chunks, with
150 characters repeated from the previous chunk. The overlap helps when an
important sentence or fact sits near a chunk boundary. Without overlap, one
chunk might contain only the first half of a fact and the next chunk only the
second half. With overlap, at least one chunk is more likely to contain the full
idea.

The `900` character size is a simple practical default, not a magic value. It is
small enough to keep retrieved context focused, but large enough to usually
contain a full paragraph or a few related sentences. Very small chunks can lose
needed context. Very large chunks can include too much unrelated material, which
makes retrieval less precise and gives the LLM noisy context.

SQLite and Qdrant use the same chunks. Chunking does not differ between them.
The difference is how the chunks are searched:

- SQLite stores the plain text plus metadata such as `source_path`, `title`, and
  `chunk_index`. SQLite retrieval uses simple token overlap against the question
  and the chunk metadata.
- Qdrant stores a vector for each chunk plus the chunk text as payload. Qdrant
  retrieval searches by vector similarity.
- Hybrid retrieval searches both, merges the best matches, removes obvious
  duplicates, and returns only the best `top_k` chunks.

When `use_rag` is enabled, the chatbot searches SQLite and Qdrant, takes the
best matching chunks, sends those chunks as context to the selected LLM, and
asks the LLM to answer from that context. The LLM does not automatically know
about every ingested file. It only sees the chunks that retrieval selected.

That means chunk quality directly affects answer quality:

- If chunks are too small, the retrieved context may not contain enough
  surrounding information.
- If chunks are too large, the retrieved context may contain too much unrelated
  information.
- If a fact is split across chunk boundaries, overlap helps keep the complete
  fact retrievable.
- If a question is vague or uses terms that do not appear in the document,
  retrieval may not find the right chunk.

PDF ingestion has an extra preparation step before normal chunking. PDF text is
extracted, cleaned, split into readable Markdown sections under
`data/uploads/prepared`, and then those prepared Markdown files are chunked and
indexed like any other text document.

In short, RAG means:

```text
retrieve a few likely relevant chunks, then let the LLM answer from those chunks
```

It does not mean:

```text
send every ingested document to the LLM
```

The current overlapping character chunks keep the implementation simple and
easy to modify while working reasonably well for README files, FAQs, notes,
uploaded text files, and prepared PDF text.

## Embeddings And Vectors

Qdrant is a vector database. It does not primarily search plain text. To use
Qdrant, the chatbot must convert text into vectors, which are lists of numbers
that represent the text in a searchable form. This conversion is usually called
embedding or vectorizing.

For example, a sentence like this:

```text
Gordon Engelke is the author of the DevOps Playground.
```

is converted into a numeric vector:

```text
[0.12, -0.03, 0.44, 0.01, ...]
```

Qdrant stores those vectors and can quickly find vectors that are close to the
question vector. With a good embedding model, texts with related meaning should
be close to each other even when they do not use exactly the same words.

In this chatbot, Qdrant ingestion currently works like this:

```text
document
  -> chunks
  -> SQLite rows
  -> local vectors
  -> Qdrant points
```

During ingestion, each chunk is stored as plain text in SQLite. If Qdrant is
enabled, the same chunk is also embedded into a vector and stored in Qdrant with
a payload containing the chunk text, source path, and chunk ID.

During RAG search, the question is embedded with the same embedding function.
Qdrant then searches for stored chunk vectors that are closest to the question
vector. The chatbot takes the matching chunk text, passes that text to the
selected LLM as context, and the LLM writes the final answer.

The LLM does not receive vectors. It receives normal text:

```text
question
  -> question vector
  -> Qdrant finds nearby chunk vectors
  -> chatbot reads matching chunk text
  -> LLM answers from the chunk text
```

The current implementation uses a small deterministic local embedding function
instead of calling OpenAI, Ollama, Anthropic, or another external embedding
model. It tokenizes the text, hashes the tokens into a fixed-size vector, and
normalizes that vector. This keeps ingestion fully local and makes Qdrant usable
without API keys, internet access, or a separately downloaded embedding model.

That local embedding is useful as a simple first version, but it is not as
semantically strong as a real embedding model. It works best when the question
and the stored chunks share related words. It is weaker for synonyms,
paraphrases, multilingual meaning, and deeper semantic similarity.

A real embedding model is not required for the current implementation, but it
would improve retrieval quality. Common production-style setups use a dedicated
embedding model for retrieval and a separate chat model for answering:

```text
embedding model: text-embedding-3-small
answer model:    gpt-4.1-mini
```

or:

```text
embedding model: nomic-embed-text via Ollama
answer model:    llama3.1 via Ollama
```

The embedding model does not need to be the same model as the answering LLM.
The important rule is that the same embedding method must be used when indexing
documents and when searching them. If documents are ingested with one embedding
model and questions are embedded with another, Qdrant compares vectors from
different numeric spaces and the results become unreliable.

Because of that, changing the embedding method requires reingesting the RAG
corpus. The Qdrant collection vector size must also match the selected
embedding model. The current local embedding uses the configured
`qdrant.vector_size` value, which defaults to `96`.

The pragmatic next improvement would be to make embeddings configurable, for
example:

```yaml
embeddings:
  provider: local_hash
  model: local-hash-96
  vector_size: 96
```

or:

```yaml
embeddings:
  provider: ollama
  model: nomic-embed-text
  vector_size: 768
```

The chatbot would then use the configured embedding provider for both ingestion
and Qdrant search. Until then, the deterministic local embedding keeps the
standalone setup simple and predictable.

## Retrieval Options Compared

The chatbot has several ways to use local knowledge. They are not strict
replacements for each other. They trade simplicity, quality, speed, and
operational cost differently.

| Source | Best at | Weak at | Speed | Overhead |
| --- | --- | --- | --- | --- |
| Direct local files | Simple access to configured files | Ranking, semantics, large corpora | Fast for small folders | Lowest |
| SQLite chunks | Exact names, commands, ports, config keys | Synonyms and paraphrases | Fast for small and medium corpora | Low |
| Qdrant with local vectors | Fully local vector path | Real semantic meaning | Fast | Medium |
| Qdrant with real embeddings | Semantic search and natural language | Setup, model/API cost, reingestion discipline | Fast search, slower ingest | Highest |

Direct local files are the simplest option. The chatbot reads configured
folders and returns snippets from matching files. This does not require
ingestion, SQLite, Qdrant, embeddings, or an LLM. It is useful for explicit file
lookup and debugging, but it has basic ranking and does not scale well to many
large files because files are read directly instead of searched through an
index.

SQLite chunks are the first indexed retrieval layer. Documents are ingested,
split into chunks, and stored in a local SQLite database. Retrieval uses simple
token overlap against chunk text and metadata. This works well for technical
playground documentation because many useful questions contain exact terms such
as `jenkins`, `gitea`, `vault`, `CHATBOT_PORT`, `OPENAI_API_KEY`, or
`make up MODE=docker`. SQLite is fast, local, predictable, and easy to inspect,
but it is mostly literal and weaker when the question uses different words than
the document.

Qdrant with the current local vectoring stores the same chunks as vectors in
Qdrant, using the deterministic local embedding function. This gives the
chatbot a real Qdrant retrieval path without external APIs, downloaded
embedding models, or extra provider configuration. It is useful as a fully local
bridge and keeps the architecture ready for stronger embeddings later. The
quality is limited because the local vectoring is not a trained semantic model.
It works best when the question and chunk share related words.

Qdrant with real embeddings is the highest-quality RAG direction. A trained
embedding model can place related meanings close together even when wording is
different. This is better for READMEs, FAQs, PDFs, ebooks, uploaded documents,
and natural-language questions. It also adds operational cost: an embedding
provider must be configured, embedding dimensions must match the Qdrant
collection, ingestion is slower, and changing the embedding model requires
resetting and reingesting the RAG corpus.

For exact technical questions, SQLite can be better than weak vector search:

```text
What is CHATBOT_PORT?
How do I start Jenkins?
What is the Vault URL?
```

For semantic questions, real embeddings are usually better:

```text
Which service stores build artifacts?
How do I shut down only the code hosting service?
Who maintains this environment?
```

Operational complexity increases in this order:

```text
direct local files
  -> SQLite chunks
  -> Qdrant with local vectors
  -> Qdrant with real embeddings
```

Ingestion cost increases in the same order. Direct local files require no
ingestion. SQLite stores chunk text. Qdrant with local vectors stores chunk text
plus cheap local vectors. Qdrant with real embeddings stores larger vectors and
must call an embedding model or API for every chunk.

The most useful mature setup for this chatbot is likely a combination:

```text
direct local files for explicit file lookup
SQLite for exact and fallback retrieval
Qdrant with real embeddings for semantic retrieval
LLM for final answer synthesis
```

The current local Qdrant vectoring is intentionally simple. It keeps the service
standalone and validates the Qdrant integration, but it should be treated as a
starter retrieval path rather than production-quality semantic search.

## Reset vs Append Ingestion

If you ingest without `reset`, the current implementation appends new chunks. It
does not replace or deduplicate previous chunks for the same document.

If you ingest the exact same document again without reset, SQLite will contain
duplicate chunks and Qdrant will contain duplicate vectors with different chunk
IDs. Retrieval may return the same content multiple times, context can become
repetitive, storage grows unnecessarily, and repeated documents can become
overrepresented in search results.

If you ingest a modified or extended document without reset, old chunks remain
and new chunks are added. That means the chatbot may retrieve stale chunks from
the older version. If old and new chunks contradict each other, the LLM may see
both and answer inconsistently. This can be acceptable for one-off additions,
but it is not a clean way to maintain a changing knowledge base.

With `reset:true`, all previous SQLite chunks are deleted, the Qdrant collection
is recreated, and the selected paths are ingested fresh. This avoids duplicates
and stale chunks, and it is the safest option after editing existing documents.
The tradeoff is that reset removes the whole current RAG corpus. If you reset
and ingest only one file, every other previously ingested document disappears
from RAG.

Use reset when rebuilding a known corpus:

```bash
curl -sS http://127.0.0.1:8088/api/ingest \
  -H 'Content-Type: application/json' \
  -d '{"paths":["sample_docs","data/uploads"],"reset":true}'
```

Use no reset only when adding new files that were not indexed before:

```bash
curl -sS http://127.0.0.1:8088/api/ingest \
  -H 'Content-Type: application/json' \
  -d '{"paths":["data/uploads/new-file.txt"],"reset":false}'
```

For edited or re-uploaded documents, prefer reset and ingest the full intended
corpus again, for example `sample_docs` plus `data/uploads`.

A future improvement would be per-document replacement: delete chunks for one
`source_path` from SQLite, delete matching Qdrant points, ingest the updated
document, and leave all other documents untouched. That is not implemented yet.

## Standalone Docker Compose

Using the Makefile:

```bash
cd chatbot
make up MODE=docker
```

This starts the sibling `ollama` service, pulls `llama3.1` if needed, and then
starts chatbot plus Qdrant.

For foreground Docker Compose output:

```bash
make docker-run
```

Manual equivalent:

```bash
cd chatbot
make -C ../ollama up MODE=docker
docker compose up --build
```

Then open:

```text
http://localhost:8088
```

Ingest sample docs in the running container:

```bash
docker compose exec chatbot python -m app.cli ingest sample_docs --reset
```

The standalone compose file starts:

- `chatbot`
- `qdrant`

The chatbot Makefile also starts:

- `ollama`

The chatbot remains useful if Qdrant or a local LLM is not available: exact rules,
pattern rules, whitelisted tools, configured local-file mode, configured SQLite
sources, and SQLite chunk retrieval still work.

## Optional Local LLM

The default local provider expects Ollama. The chatbot Makefile starts the
Docker-based `../ollama` service automatically and ensures this model is
available:

```bash
llama3.1
```

The default local LLM timeout is 180 seconds because the first request can spend
time loading the model and CPU-only inference may be slow.

In bare chatbot mode, the default URL is:

```text
http://localhost:11434/api/chat
```

In Docker chatbot mode, `LOCAL_LLM_URL` defaults to:

```text
http://playground-ollama:11434/api/chat
```

The Docker chatbot and Docker Ollama services use the shared Docker network
`playground-llm`, which avoids accidentally talking to a host-installed Ollama
on the same port.

If you prefer a host-installed Ollama instead of the Docker service, disable the
automatic dependency and run Ollama yourself:

```bash
ollama serve
ollama pull llama3.1
CHATBOT_START_OLLAMA=false make run MODE=bare
```

You can also point `providers.local.base_url` at an OpenAI-compatible local
`/chat/completions` endpoint.

## OpenAI and Anthropic

OpenAI is the default provider in `config/config.yml`, so set an OpenAI key for
normal LLM-backed answers:

```bash
export OPENAI_API_KEY=...
```

Set an Anthropic key only when you want to use that provider:

```bash
export ANTHROPIC_API_KEY=...
```

You can still select a provider per request or change the default in config:

```yaml
providers:
  default_provider: openai
  default_model: gpt-4.1-mini
```

Fixed rules and whitelisted tools do not call an LLM.

## Configuration

Most behavior is in `config/config.yml`.

Add an exact rule:

```yaml
rules:
  exact:
    - question: "How are you?"
      answer: "I'm fine"
```

Add a regex rule:

```yaml
rules:
  patterns:
    - pattern: "^help$"
      answer: "Try local time, list sample docs, or ask about Jenkins."
```

Add a whitelisted host command:

```yaml
tools:
  - name: local_time
    match:
      exact: ["local time"]
    command: ["python", "-c", "import datetime; print(datetime.datetime.now().isoformat())"]
    timeout_seconds: 5
```

Commands are never built from user input. A user message can only select a tool
that is explicitly configured.

## Integrating With The DevOps Playground

The chatbot does not hardcode Jenkins, Gitea, Nexus, Vault, or any other service.
Add REST integrations in config:

```yaml
rest_sources:
  - name: jenkins_health
    enabled: true
    url: http://jenkins:8080/login
    method: GET
    send_query_param: false
    timeout_seconds: 3
    match:
      patterns:
        - "jenkins health"
        - "jenkins status"
```

Add a SQLite source:

```yaml
sqlite_sources:
  - name: local_inventory
    enabled: true
    path: data/inventory.sqlite
    query: "SELECT service, status FROM services WHERE service LIKE :like_query LIMIT 5"
    limit: 5
    match:
      patterns:
        - "inventory"
        - "service status"
```

Add local documents:

```yaml
local_files:
  - name: runbooks
    enabled: true
    path: docs/runbooks
    match:
      patterns:
        - "runbook"
        - "incident"
```

No Python code changes are needed for these integrations.

## Compose Extension Example

In a larger playground compose file, add the chatbot service and point it at the
same network as the other services:

```yaml
services:
  chatbot:
    build: ./chatbot
    ports:
      - "8088:8088"
    environment:
      CHATBOT_CONFIG: /app/config/config.yml
      QDRANT_URL: http://qdrant:6333
      JENKINS_URL: http://jenkins:8080
      GITEA_URL: http://gitea:3000
      NEXUS_URL: http://nexus:8081
    volumes:
      - ./chatbot/config:/app/config:ro
      - ./chatbot/sample_docs:/app/sample_docs:ro
      - chatbot-data:/app/data

  qdrant:
    image: qdrant/qdrant:v1.12.4
    volumes:
      - qdrant-data:/qdrant/storage

volumes:
  chatbot-data:
  qdrant-data:
```

Then reference those environment variables from `config/config.yml`:

```yaml
rest_sources:
  - name: jenkins_health
    enabled: true
    url: ${JENKINS_URL}/login
    method: GET
    send_query_param: false
    match:
      patterns: ["jenkins health"]
```

## Web Search

Web search is disabled by default:

```yaml
web_search:
  enabled: false
```

Enable it only in environments where outbound internet access is expected:

```yaml
web_search:
  enabled: true
```

The current implementation uses DuckDuckGo's instant answer endpoint and degrades
gracefully if the network is unavailable.

## Tests

```bash
cd chatbot
pytest
```

The tests cover exact rules, pattern rules, whitelisted commands, SQLite chunk
retrieval, PDF preparation, and the API health/chat/upload endpoints.

## Next Sensible Improvements

- Add optional stronger local embeddings, for example sentence-transformers, while keeping the deterministic embedding as fallback.
- Add authentication for REST sources that need tokens, loaded from environment variables.
- Add a small admin endpoint for listing configured sources and checking their health.
- Add streaming responses for LLM calls after the basic API contract is stable.
