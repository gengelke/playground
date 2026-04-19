# Local-first Chatbot

> [!WARNING]
> This service is an experimental setup for educational purposes only.
> Do not expose any part of it to the public internet.
> It uses insecure defaults such as default passwords and other convenience settings that are only acceptable for isolated local testing.

> [!IMPORTANT]
> Parts of this service were generated with AI assistance.
> Review generated code and configuration carefully before using or modifying this service.

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
    static/chat.html
    static/ingest.html
    static/app.js
    static/styles.css
    static/index.html redirect to /chat
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

That creates `.venv`, installs `requirements.txt`, starts the sibling `qdrant`
and `ollama` services, pulls `llama3.1` if needed, and starts uvicorn in the
foreground. Qdrant vector data is preserved on the host under `qdrant/data`;
Ollama model data is preserved under `ollama/data`.

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
# or, if python3.12 is not installed:
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

The Makefile prefers `python3.12`, then `python3.11`, then `python3.10`. You
can also override it explicitly, for example `make PYTHON=python3.11 ingest`.

For the local RAG and LLM paths, also start Qdrant and Ollama:

```bash
make -C ../qdrant up MODE=docker
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
export CHATBOT_COMMAND_TOKEN='change-me-to-a-long-random-secret'
python -m app.cli ask "Simon says get time"
```

Interactive mode:

```bash
python -m app.cli shell
```

Question history:

```bash
python -m app.cli history list --limit 20
python -m app.cli history show 1
python -m app.cli history delete 1
python -m app.cli history clear
```

Select a provider and model:

```bash
python -m app.cli ask "Explain these Jenkins notes" --provider openai --model gpt-4.1-mini --force-llm
python -m app.cli ask "Explain these Jenkins notes" --provider anthropic --model claude-sonnet-4-6 --force-llm
python -m app.cli ask "Explain these Jenkins notes" --provider local --model llama3.1 --force-llm
```

If no provider or model is supplied, `config/config.yml` decides.

Ask with a specific retrieval profile:

```bash
python -m app.cli ask "Who maintains the playground?" --retrieval-profile sqlite --provider openai --model gpt-4.1-mini
python -m app.cli ask "Who maintains the playground?" --retrieval-profile qdrant_local_hash --provider openai --model gpt-4.1-mini
```

Compare the same question against multiple retrieval profiles:

```bash
python -m app.cli compare "Who maintains the playground?" \
  --profiles sqlite,qdrant_local_hash,qdrant_openai,qdrant_anthropic_openai \
  --provider anthropic
```

## REST Usage

```bash
curl -s http://localhost:8088/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"message":"How are you?"}' | jq
```

Authenticated command execution:

```bash
curl -s http://localhost:8088/api/chat \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${CHATBOT_COMMAND_TOKEN}" \
  -d '{"message":"Simon says get time"}' | jq
```

## VIP Command Token

The chatbot has two different usage levels:

- Public usage: normal questions, deterministic rules, RAG, local files, SQLite,
  Qdrant, web search, and LLM-backed answers.
- VIP usage: local command execution through configured `Simon says ...`
  commands.

Public usage does not require authentication. A user can ask questions through
the web UI, REST API, or CLI without a token.

VIP usage requires a bearer token because commands can interact with the host or
with other playground services. This protects commands such as:

- `Simon says get time`
- `Simon says get statistics`
- `Simon says get docs`
- `Simon says get employees`
- `Simon says add employee <name> <surname> <role>`
- `Simon says delete employee <employeeId>`

The sample config enables this command protection:

```yaml
auth:
  command_auth_required: true
  command_token_env: CHATBOT_COMMAND_TOKEN
```

Set the token in `chatbot/.env` for Docker Compose:

```env
CHATBOT_COMMAND_TOKEN=change-me-to-a-long-random-secret
```

Then restart the chatbot:

```bash
docker compose up --build -d
```

For the CLI, either export the same environment variable:

```bash
export CHATBOT_COMMAND_TOKEN='change-me-to-a-long-random-secret'
python -m app.cli ask "Simon says get time"
```

or pass it directly:

```bash
python -m app.cli ask "Simon says get time" \
  --command-token 'change-me-to-a-long-random-secret'
```

For REST, send the token as a bearer token:

```bash
curl -s http://localhost:8088/api/chat \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer change-me-to-a-long-random-secret' \
  -d '{"message":"Simon says get time"}' | jq
```

For the web UI, enter the token in the `VIP command token` field before running
a `Simon says ...` command. The field is optional for normal questions.

If command authentication is enabled and the token is missing, invalid, or not
configured in the environment, the command is not executed. The chatbot returns
`source=auth` with metadata explaining why it was blocked.

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

History endpoints:

```bash
curl -s http://localhost:8088/api/history?limit=20 | jq
curl -s http://localhost:8088/api/history/1 | jq
curl -s -X DELETE http://localhost:8088/api/history/1 | jq
curl -s -X DELETE http://localhost:8088/api/history | jq
```

The chat web UI has a history panel. Refresh loads recent entries, selecting an
entry or pressing Use copies only the selected question into the question field,
and Clear removes stored history. The optional VIP command token field is only
needed for `Simon says ...` commands; normal questions can be submitted without
authentication.

## Retrieval Profile Experiments

Retrieval profiles make it possible to ask the same question against different
knowledge sources and embedding strategies. The configured profiles live in
`config/config.yml` under `retrieval.profiles`.

This is intended for direct RAG experiments. You can keep the answering model
the same, for example Anthropic or OpenAI, and change only the retrieval
profile. That lets you compare whether the answer changes because the chatbot
used direct local files, SQLite token matching, Qdrant with the built-in local
hash vectors, Qdrant with OpenAI embeddings, Qdrant with Ollama embeddings, or
Qdrant with OpenAI embeddings for Anthropic-backed answering.

The default profiles are:

- `local_files`: reads configured local files directly.
- `sqlite`: searches ingested SQLite chunks by token overlap.
- `hybrid`: searches `qdrant_local_hash` and `sqlite`, then merges results.
- `qdrant_local_hash`: searches Qdrant vectors created with the built-in local
  hash embedding.
- `qdrant_openai`: searches a separate Qdrant collection created with OpenAI
  embeddings.
- `qdrant_ollama`: searches a separate Qdrant collection created with Ollama
  embeddings.
- `qdrant_anthropic_openai`: searches a separate Qdrant collection created with
  OpenAI embeddings and is intended for Anthropic answer generation paired with
  a real embedding model already present in this setup.

Each Qdrant embedding strategy uses its own collection. Do not mix local hash,
OpenAI, and Ollama embeddings in one Qdrant collection because their vectors
are not comparable.

OpenAI embedding ingestion requires `OPENAI_API_KEY`. Ollama embedding ingestion
uses `nomic-embed-text`; the chatbot Makefile pulls that model when it starts
the sibling Ollama service. Anthropic does not provide its own embedding model;
the `qdrant_anthropic_openai` profile reuses OpenAI embeddings so Anthropic
answers can still run against a real semantic retrieval index.

Retrieval profiles are not LLM providers. For example,
`qdrant_anthropic_openai` controls where context is retrieved from; the selected
provider still controls which LLM answers. If `provider=anthropic` is selected
without `ANTHROPIC_API_KEY`, the chatbot returns `source=llm_error` and keeps
the retrieved context in metadata for debugging instead of presenting raw RAG
context as if it were an Anthropic answer.

List configured profiles:

```bash
curl -s http://localhost:8088/api/retrieval-profiles | jq
```

Ask one question with one profile:

```bash
curl -s http://localhost:8088/api/chat \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Who maintains the playground?",
    "retrieval_profile": "sqlite",
    "provider": "openai",
    "model": "gpt-4.1-mini",
    "use_rag": true
  }' | jq
```

Compare one question across several profiles:

```bash
curl -s http://localhost:8088/api/chat/compare \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Who maintains the playground?",
    "provider": "openai",
    "model": "gpt-4.1-mini",
    "retrieval_profiles": ["sqlite", "qdrant_local_hash", "qdrant_openai", "qdrant_anthropic_openai"]
  }' | jq
```

The web UI exposes the same controls. Choose one retrieval profile for normal
chat, or enable compare mode and select multiple profiles to see answers,
metadata, retrieved context, and latency in one response.

The compare response is useful because it shows more than the final text. For
each selected profile, inspect:

- `answer`: what the selected LLM answered from the retrieved context.
- `metadata.context`: which chunks or local-file snippets were sent to the LLM.
- `metadata.retrieval.profile`: which profile was used.
- `metadata.retrieval.embedding`: which embedding provider/model was used for
  Qdrant profiles.
- `metadata.retrieval.latency_ms`: how long retrieval took.
- `metadata.llm.latency_ms`: how long answer generation took.

This separation is important: retrieval profiles decide which data reaches the
LLM, while `provider` and `model` decide which LLM writes the final answer.
Changing only the retrieval profile is the easiest way to compare local files,
SQLite, homemade vectors, and real embeddings against the same question.

## Ingestion Flow

Ingestion stores chunks in SQLite and, when Qdrant is enabled and reachable,
also stores vectors in the selected Qdrant retrieval profiles. The default
ingest profiles are `sqlite` and `qdrant_local_hash`, so normal ingestion still
works without OpenAI, Anthropic, or a local LLM.

SQLite and Qdrant retrieval have simple relevance gates in `config/config.yml`:
`min_query_chars`, `min_query_tokens`, and `min_score`. This prevents very short
or unrelated questions from always returning stored chunks. The `use_rag` flag
controls whether document chunks are added to LLM context. Raw chunks are only
returned as a fallback if the selected LLM is unavailable.

Qdrant retrieval first asks Qdrant for more candidates than the final `top_k`
and then applies a small language-agnostic lexical rerank. This helps direct
command questions such as "how do I start the playground" surface chunks that
contain the matching command, even when the raw vector score ranks a broader
overview chunk higher. The relevant knobs are `candidate_multiplier`,
`min_candidates`, `lexical_rerank_weight`, and `lexical_min_score` under
`qdrant` in `config/config.yml`. Set `lexical_rerank_weight` to `0` if you want
to inspect raw vector ranking only.

```bash
python -m app.cli ingest sample_docs --reset
python -m app.cli ingest sample_docs --reset --profiles sqlite,qdrant_local_hash,qdrant_openai,qdrant_anthropic_openai
python -m app.cli ask "Jenkins REST API playground note"
```

The Makefile helper accepts the same profile list:

```bash
make ingest PATHS='sample_docs' PROFILES='sqlite,qdrant_local_hash,qdrant_openai,qdrant_anthropic_openai'
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

The web UI is split into `http://localhost:8088/chat` and
`http://localhost:8088/ingest`. The root path redirects to `/chat`. Use the
ingest page to enter one server-visible path per line, for example
`sample_docs`. In Docker mode, paths must exist inside the chatbot container or
be mounted into it. The same page can also upload files selected in the
browser. Uploaded files are stored under `data/uploads` inside the chatbot
service and then ingested into SQLite/Qdrant. PDF uploads are extracted,
cleaned, converted to Markdown under `data/uploads/prepared`, and then
ingested from that prepared text.

Supported document inputs are text-like files (`.txt`, `.md`, `.json`, `.yaml`,
`.csv`, `.html`, logs), simple `.epub` text extraction, and `.pdf` preparation
through `pypdf`. The PDF path removes repeated header/footer lines, page number
lines, fixes common hyphenated line breaks, normalizes paragraphs, writes
Markdown sections, and ingests those sections. Temporary/editor files such as
`.swp`, `.un~`, `.bak`, and files ending in `~` are skipped so stale editor
state does not become RAG context.

## Inspecting Ingested Data

The chatbot keeps ingested chunks in SQLite and stores Qdrant vectors in one
collection per Qdrant retrieval profile. There is no dedicated document catalog
API yet, but the stored data can be inspected directly.

List documents currently stored in the SQLite chunk store:

```bash
cd chatbot
sqlite3 data/documents.sqlite "
select
  source_path,
  count(*) as chunks,
  datetime(min(created_at), 'unixepoch', 'localtime') as first_ingested,
  datetime(max(created_at), 'unixepoch', 'localtime') as last_ingested
from chunks
group by source_path
order by max(created_at) desc;
"
```

This shows each ingested source path, how many chunks it produced, and when the
oldest/newest chunk rows for that document were inserted.

Show chunk previews for one document:

```bash
sqlite3 data/documents.sqlite "
select chunk_index, substr(text, 1, 160) as preview
from chunks
where source_path = 'sample_docs/playground-faq.md'
order by chunk_index;
"
```

This is useful when checking whether the prepared text from a PDF or upload
contains the expected content before debugging retrieval quality.

Check whether repeated ingestion created duplicate chunk rows:

```bash
sqlite3 data/documents.sqlite "
select source_path, chunk_index, count(*) as copies
from chunks
group by source_path, chunk_index
having count(*) > 1
order by copies desc, source_path, chunk_index;
"
```

Duplicates are expected if the same file is ingested repeatedly without
`reset:true`; they can make retrieval repetitive.

List Qdrant collections:

```bash
curl -s http://127.0.0.1:6333/collections | jq
```

Inspect one Qdrant collection:

```bash
curl -s http://127.0.0.1:6333/collections/chatbot_chunks_openai | jq
```

Qdrant can show collection status and point counts. The current Qdrant payloads
store `text`, `source_path`, and `chunk_id`, but not a full ingest history.

The same basic inspection is also available through the whitelisted chatbot
command:

```bash
python -m app.cli ask "Simon says get statistics"
```

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
  -> profile-specific embeddings
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

The current implementation supports multiple embedding strategies through
retrieval profiles:

- `qdrant_local_hash`: small deterministic local token-hash vectors
- `qdrant_openai`: OpenAI embeddings
- `qdrant_ollama`: Ollama embeddings via `nomic-embed-text`
- `qdrant_anthropic_openai`: OpenAI embeddings paired with Anthropic answer
  generation

The local-hash embedding keeps ingestion fully local and makes Qdrant usable
without API keys, internet access, or a separately downloaded embedding model.
It tokenizes the text, hashes the tokens into a fixed-size vector, and
normalizes that vector.

That local embedding is useful as a simple baseline, but it is not as
semantically strong as a real embedding model. It works best when the question
and the stored chunks share related words. It is weaker for synonyms,
paraphrases, multilingual meaning, and deeper semantic similarity.

Real embedding models are already supported and generally improve retrieval
quality. Common production-style setups use a dedicated embedding model for
retrieval and a separate chat model for answering:

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
documents and when searching them within one retrieval profile. If documents are
ingested with one embedding model and questions are embedded with another,
Qdrant compares vectors from different numeric spaces and the results become
unreliable.

Because of that, changing the embedding method for a profile requires
reingesting that profile's RAG corpus. The Qdrant collection vector size must
also match the selected embedding model. This is already configured per profile
under `retrieval.profiles`, for example:

```yaml
- name: qdrant_local_hash
  type: qdrant
  collection: chatbot_chunks_local_hash
  embedding:
    provider: local_hash
    model: local-hash-96
    vector_size: 96

- name: qdrant_ollama
  type: qdrant
  collection: chatbot_chunks_ollama
  embedding:
    provider: ollama
    model: nomic-embed-text
    vector_size: 768
```

This keeps the setup simple while still letting you compare a fully local
baseline with stronger semantic embeddings.

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

This starts the sibling `qdrant` service, starts the sibling `ollama` service,
pulls `llama3.1` if needed, and then starts the chatbot.

For foreground Docker Compose output:

```bash
make docker-run
```

Manual equivalent:

```bash
cd chatbot
make -C ../qdrant up MODE=docker
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

The chatbot Makefile also starts:

- `qdrant`
- `ollama`

The standalone Qdrant service can also be started directly:

```bash
cd qdrant
make up MODE=docker
```

The chatbot remains useful if Qdrant or a local LLM is not available: exact
rules, pattern rules, whitelisted tools, configured local-file mode, configured
SQLite sources, and SQLite chunk retrieval still work.

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
http://127.0.0.1:11435/api/chat
```

In Docker chatbot mode, `LOCAL_LLM_URL` defaults to:

```text
http://playground-ollama:11434/api/chat
```

The Docker chatbot and Docker Ollama services use the shared Docker network
`playground-llm`, which avoids accidentally talking to a host-installed Ollama
on the same port.

The Docker chatbot and Docker Qdrant services use the shared Docker network
`playground-vector`. In Docker chatbot mode, `QDRANT_URL` defaults to:

```text
http://playground-qdrant:6333
```

On the host, the playground Qdrant service is exposed through `QDRANT_URL`,
which defaults to:

```text
http://127.0.0.1:6333
```

The bare-mode chatbot Makefile points at the playground Ollama Docker service on
`OLLAMA_URL`, which defaults to `http://127.0.0.1:11435`. This keeps it
separate from a host-installed Ollama that may already be using `11434`.

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

If an OpenAI or Anthropic request fails, the chatbot returns `source=llm_error`.
The metadata includes `metadata.llm.status_code`, `metadata.llm.response_text`,
and `metadata.llm.response_json` when the provider returned an HTTP error body.
Those fields are useful for diagnosing invalid model names, account access
issues, request validation errors, or provider-side failures.

For Docker Compose, start from the provided environment template:

```bash
cp .env.template .env
```

Then edit `.env` locally and set only the providers you want to use. Do not
commit real API keys.

Set a command token when you want to allow VIP command execution:

```bash
CHATBOT_COMMAND_TOKEN=change-me-to-a-long-random-secret
```

Normal questions do not require this token. Only `Simon says ...` commands use
it.

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
      answer: "Try Simon says get time, Simon says get statistics, Simon says get docs, or Simon says get employees."
```

Add a whitelisted host command:

```yaml
tools:
  - name: local_time
    match:
      exact: ["get time"]
    command: ["{python}", "-m", "app.tool_commands", "time"]
    timeout_seconds: 5
```

Commands are never built from user input. A user message can only select a tool
that is explicitly configured. Tool execution also requires the message to start
with `Simon says`.

The sample config requires authentication for command execution:

```yaml
auth:
  command_auth_required: true
  command_token_env: CHATBOT_COMMAND_TOKEN
```

Without a valid bearer token, public users can still ask normal questions, but
`Simon says ...` commands return `source=auth` and are not executed. CLI usage
can pass `--command-token` or use the `CHATBOT_COMMAND_TOKEN` environment
variable. REST and the web UI send the same value as a bearer token.

The sample config includes these commands:

- `Simon says get time`: prints the host/container system time.
- `Simon says get statistics`: prints SQLite ingestion summaries, duplicate
  chunk checks, and Qdrant collection status.
- `Simon says get docs`: lists files in the configured example docs directory.
- `Simon says get employees`: uses the generated playground GraphQL client
  library from `api/graphql-library/generated` and returns the current
  employees from the API service. In Docker mode, that generated library is
  mounted read-only into the chatbot container.
- `Simon says add employee <name> <surname> <role>`: adds an employee through
  the playground GraphQL API. The chatbot generates the employee ID. Quote the
  role if it contains spaces, for example `Simon says add employee Erika
  Mustermann "Senior Developer"`.
- `Simon says delete employee <employeeId>`: deletes the employee with that ID
  through the playground GraphQL API.

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
same networks as the other services and the standalone Qdrant service:

```yaml
services:
  chatbot:
    build: ./chatbot
    ports:
      - "8088:8088"
    environment:
      CHATBOT_CONFIG: /app/config/config.yml
      QDRANT_URL: http://playground-qdrant:6333
      JENKINS_URL: http://jenkins:8080
      GITEA_URL: http://gitea:3000
      NEXUS_URL: http://nexus:8081
    volumes:
      - ./chatbot/config:/app/config:ro
      - ./chatbot/sample_docs:/app/sample_docs:ro
      - chatbot-data:/app/data
    networks:
      - playground-vector

volumes:
  chatbot-data:

networks:
  playground-vector:
    external: true
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
