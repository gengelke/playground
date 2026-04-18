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

The web UI at `http://localhost:8088/` also has an ingestion form. Enter one
server-visible path per line, for example `sample_docs`. In Docker mode, paths
must exist inside the chatbot container or be mounted into it. The same form can
also upload files selected in the browser. Uploaded files are stored under
`data/uploads` inside the chatbot service and then ingested into SQLite/Qdrant.

Supported document inputs are text-like files (`.txt`, `.md`, `.json`, `.yaml`,
`.csv`, `.html`, logs) and simple `.epub` text extraction. PDFs are not parsed in
this first version; convert them to text before ingestion. Temporary/editor files
such as `.swp`, `.un~`, `.bak`, and files ending in `~` are skipped so stale
editor state does not become RAG context.

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
retrieval, and the API health/chat endpoints.

## Next Sensible Improvements

- Add PDF extraction with a small optional dependency such as `pypdf`.
- Add optional stronger local embeddings, for example sentence-transformers, while keeping the deterministic embedding as fallback.
- Add authentication for REST sources that need tokens, loaded from environment variables.
- Add a small admin endpoint for listing configured sources and checking their health.
- Add streaming responses for LLM calls after the basic API contract is stable.
