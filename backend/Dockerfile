# Roam API – Cloud Run
FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Application code (app/ must be at /app/app for uvicorn app.api.app:app)
COPY app ./app

# Cloud Run sets PORT; default 8080 for local runs
ENV PORT=8080
EXPOSE 8080

CMD uvicorn app.api.app:app --host 0.0.0.0 --port ${PORT}
