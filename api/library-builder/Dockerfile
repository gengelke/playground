FROM python:3.11-slim

# Install curl
RUN apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir ariadne-codegen==0.16.0

COPY generate-client.sh /generate-client.sh
RUN chmod +x /generate-client.sh

CMD ["bash"]
