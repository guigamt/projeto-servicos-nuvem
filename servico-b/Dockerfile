FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY worker.py .

ENV PYTHONUNBUFFERED=1

# o servico B nao abre nenhuma porta, ele so conecta no rabbitmq
CMD ["python", "worker.py"]
