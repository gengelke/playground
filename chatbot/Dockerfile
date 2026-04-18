FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV CHATBOT_CONFIG=/app/config/config.yml

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app app
COPY config config
COPY sample_docs sample_docs

RUN mkdir -p data

EXPOSE 8088

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8088"]

