# nginx

> [!WARNING]
> This service is an experimental setup for educational purposes only.
> Do not expose any part of it to the public internet.
> It uses insecure defaults such as default passwords and other convenience settings that are only acceptable for isolated local testing.

> [!IMPORTANT]
> Parts of this service were generated with AI assistance.
> Review generated code and configuration carefully before using or modifying this service.

Local HTTPS nginx service for the playground.

It serves a static example page at:

```bash
https://localhost:8443
```

The page displays the same image referenced at the top of the repository README.

## Usage

Start nginx:

```bash
make up MODE=docker
```

Stop nginx:

```bash
make down MODE=docker
```

Show status:

```bash
make status MODE=docker
```

## TLS

Startup generates a local self-signed certificate under:

```bash
nginx/.state/tls/
```

Browsers will warn because the certificate is self-signed. Accept the warning for local testing only.

The HTTPS host port is configured centrally in:

```bash
ports.env
```
