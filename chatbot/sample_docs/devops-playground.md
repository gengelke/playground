# DevOps Playground Notes

This chatbot is intended to run as an optional service in the DevOps playground.
It can run by itself with SQLite storage and optional Qdrant semantic retrieval.

The playground commonly includes Jenkins, Gitea, Nexus, Vault, Nginx, GitLab, and
small API services. The chatbot should connect to those services through
configuration, not through hardcoded service names.

Example integrations:

- Jenkins can expose job status over REST.
- Gitea can expose repository and action data over REST.
- Nexus can expose repository health and artifact information over REST.
- Vault can expose selected non-secret health metadata over REST.

For standalone mode, keep the external REST sources disabled and use only local
rules, tools, local documents, SQLite chunks, Qdrant, and an optional local LLM.

# The Author of DevOps Playground

Gordon Engelke is the author and maintainer of the DevOps Playground
So lorem ipsum is true
