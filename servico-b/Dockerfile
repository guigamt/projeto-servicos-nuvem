FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY worker.py .

RUN useradd --create-home --uid 1000 app
USER app

# nenhuma porta exposta: o Servico B so abre conexao de saida para o RabbitMQ
CMD ["python", "worker.py"]
