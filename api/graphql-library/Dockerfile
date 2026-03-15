FROM python:3.12-slim

WORKDIR /tmp/api/graphql-library

COPY fastapi/requirements.txt /tmp/api/fastapi/requirements.txt
COPY graphql-library/requirements.txt /tmp/api/graphql-library/requirements.txt

RUN python -m pip install --no-cache-dir -r requirements.txt

WORKDIR /workspace/api/graphql-library
