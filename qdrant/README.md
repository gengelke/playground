# Qdrant

> [!WARNING]
> This service is an experimental setup for educational purposes only.
> Do not expose any part of it to the public internet.
> It uses insecure defaults such as unauthenticated local access and other convenience settings that are only acceptable for isolated local testing.

> [!IMPORTANT]
> Parts of this service were generated with AI assistance.
> Review generated code and configuration carefully before using or modifying this service.

This service runs Qdrant as the playground vector database. It can be started
independently from the chatbot and reused by other local services that need
vector storage or semantic retrieval.

Qdrant data is stored on the host under:

```text
qdrant/data
```

The data directory is mounted into the container as `/qdrant/storage`, so
collections survive container restarts and container recreation.

## Start

```bash
cd qdrant
make up MODE=docker
```

Qdrant is exposed on the host through the central `QDRANT_PORT` setting in
`ports.env`, defaulting to:

```text
http://127.0.0.1:6333
```

Check collections:

```bash
curl -s http://127.0.0.1:6333/collections | jq
```

## Stop

```bash
make down MODE=docker
```

This stops the container but keeps `qdrant/data`.

## Remove Everything

```bash
make distclean
```

This removes the container and `qdrant/data`.

## Chatbot Integration

The chatbot uses Qdrant through:

```text
http://playground-qdrant:6333
```

The Docker chatbot and Docker Qdrant services share the external Docker network:

```text
playground-vector
```

The Qdrant Makefile creates that network automatically before starting the
container.

The chatbot Makefile starts this service automatically before starting the
chatbot, unless disabled with:

```bash
CHATBOT_START_QDRANT=false make -C chatbot up MODE=docker
```
