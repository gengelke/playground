FROM jenkins/inbound-agent:latest-jdk21

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      curl \
      git \
      jq \
      make \
      python3 \
      python3-pip \
      python3-venv \
    && rm -rf /var/lib/apt/lists/*

COPY start-agent.sh /usr/local/bin/start-agent.sh
RUN chmod 0755 /usr/local/bin/start-agent.sh

USER jenkins
ENTRYPOINT ["/usr/local/bin/start-agent.sh"]
