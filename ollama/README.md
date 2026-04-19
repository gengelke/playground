# Ollama

> [!WARNING]
> This service is an experimental setup for educational purposes only.
> Do not expose any part of it to the public internet.
> It uses insecure defaults such as default passwords and other convenience settings that are only acceptable for isolated local testing.

> [!IMPORTANT]
> Parts of this service were generated with AI assistance.
> Review generated code and configuration carefully before using or modifying this service.

This service runs Ollama for the playground and keeps pulled models on the host
under `ollama/data`, mounted into the container as `/root/.ollama`. The model
cache survives container restarts and container recreation.

## Start

```bash
cd ollama
make up MODE=docker
```

The Makefile starts the container, waits for `/api/tags`, and pulls:

```text
llama3.1
```

Override the model if needed:

```bash
make up MODE=docker OLLAMA_MODEL=mistral
```

## Stop

```bash
make down MODE=docker
```

This stops the container but keeps `ollama/data`, so models are not downloaded
again on the next start.

## Remove Everything

```bash
make distclean
```

This removes the container and `ollama/data`.

## Chatbot Integration

The chatbot uses Ollama through:

```text
http://playground-ollama:11434/api/chat
```

On the host, the playground Ollama service is exposed through `OLLAMA_URL`,
which defaults to:

```text
http://127.0.0.1:11435
```

The Docker chatbot and Docker Ollama services share the external Docker network
`playground-llm`. The Ollama Makefile creates that network automatically before
starting the container.

The chatbot Makefile starts this service automatically before starting the
chatbot, unless disabled with:

```bash
CHATBOT_START_OLLAMA=false make -C chatbot up MODE=docker
```
