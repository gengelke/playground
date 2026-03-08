FROM jenkins/inbound-agent:latest-jdk17

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

USER jenkins
COPY start-agent.sh /usr/local/bin/start-agent.sh
ENTRYPOINT ["/usr/local/bin/start-agent.sh"]
