# Servico B - pega os pedidos da fila e processa (consumidor)
# Ele NAO conhece o servico A, so conhece o rabbitmq e o nome da fila.

import json
import os
import signal
import sys
import time

import pika

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_USER = os.getenv("RABBITMQ_USER")
RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD")
FILA = "pedidos"
# quanto tempo cada pedido "demora" pra ser processado (em segundos)
TEMPO_PROCESSAMENTO = float(os.getenv("TEMPO_PROCESSAMENTO", "1"))
NOME = os.getenv("HOSTNAME", "servico-b")  # nome do container/pod, pra saber quem processou


def processar(canal, metodo, propriedades, corpo):
    pedido = json.loads(corpo)
    print(f"[B {NOME}] request_id={pedido['request_id']} pedido {pedido['id']} recebido da fila "
          f"(cliente={pedido['cliente']}, produto={pedido['produto']})")

    # simula um processamento pesado (tipo calcular frete / gerar nota fiscal)
    # fica fazendo conta pra gastar CPU, assim o HPA consegue ver a carga
    fim = time.time() + TEMPO_PROCESSAMENTO
    while time.time() < fim:
        sum(i * i for i in range(1000))

    # so confirma (ack) depois de processar. se o worker cair antes disso a mensagem volta pra fila
    canal.basic_ack(delivery_tag=metodo.delivery_tag)
    print(f"[B {NOME}] request_id={pedido['request_id']} pedido {pedido['id']} processado")


def parar(sinal, frame):
    # quando o docker/kubernetes manda parar o container
    print(f"[B {NOME}] desligando...")
    sys.exit(0)


signal.signal(signal.SIGTERM, parar)

while True:
    try:
        credenciais = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
        conexao = pika.BlockingConnection(pika.ConnectionParameters(host=RABBITMQ_HOST, credentials=credenciais))
        canal = conexao.channel()
        canal.queue_declare(queue=FILA, durable=True)

        # cada worker pega 1 mensagem por vez, assim divide certinho entre as replicas
        canal.basic_qos(prefetch_count=1)
        canal.basic_consume(queue=FILA, on_message_callback=processar)

        print(f"[B {NOME}] conectado no rabbitmq, esperando pedidos...")
        canal.start_consuming()
    except pika.exceptions.AMQPConnectionError:
        print(f"[B {NOME}] nao consegui conectar no rabbitmq, tentando de novo em 5s")
        time.sleep(5)
