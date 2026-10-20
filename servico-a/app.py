# Servico A - recebe os pedidos e manda pra fila do RabbitMQ (produtor)
# Ele NAO conhece o servico B, so conhece o rabbitmq e o nome da fila.

import json
import os
import uuid
from datetime import datetime

import pika
from flask import Flask, jsonify, request, send_file

app = Flask(__name__)

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_USER = os.getenv("RABBITMQ_USER")
RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD")
FILA = "pedidos"


def enviar_para_fila(mensagem):
    # abre uma conexao, publica e fecha (simples, e se o rabbit reiniciar nao tem problema)
    credenciais = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
    conexao = pika.BlockingConnection(pika.ConnectionParameters(host=RABBITMQ_HOST, credentials=credenciais))
    canal = conexao.channel()

    # durable=True -> a fila continua existindo se o rabbitmq reiniciar
    canal.queue_declare(queue=FILA, durable=True)
    # confirm_delivery -> o rabbit confirma que recebeu a mensagem
    canal.confirm_delivery()

    canal.basic_publish(
        exchange="",
        routing_key=FILA,
        body=json.dumps(mensagem),
        properties=pika.BasicProperties(delivery_mode=2),  # 2 = mensagem persistente (salva no disco)
    )
    conexao.close()


@app.route("/")
def pagina():
    return send_file("index.html")


@app.route("/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/fila")
def ver_fila():
    # mostra quantos pedidos estao esperando na fila e quantos servicos B estao conectados
    try:
        credenciais = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
        conexao = pika.BlockingConnection(pika.ConnectionParameters(host=RABBITMQ_HOST, credentials=credenciais))
        fila = conexao.channel().queue_declare(queue=FILA, durable=True, passive=True)
        conexao.close()
        return jsonify({"esperando": fila.method.message_count, "consumidores": fila.method.consumer_count})
    except Exception:
        return jsonify({"erro": "rabbitmq indisponivel"}), 503


@app.route("/pedidos", methods=["POST"])
def criar_pedido():
    # o nginx manda esse id no header, assim da pra seguir o pedido nos logs
    request_id = request.headers.get("X-Request-ID", uuid.uuid4().hex)
    dados = request.get_json(silent=True) or {}

    cliente = dados.get("cliente")
    produto = dados.get("produto")
    quantidade = dados.get("quantidade", 1)

    if not cliente or not produto:
        return jsonify({"erro": "cliente e produto sao obrigatorios"}), 400

    print(f"[A] request_id={request_id} pedido recebido: cliente={cliente} produto={produto} qtd={quantidade}")

    pedido = {
        "id": uuid.uuid4().hex[:8],
        "request_id": request_id,
        "cliente": cliente,
        "produto": produto,
        "quantidade": quantidade,
        "criado_em": datetime.now().isoformat(timespec="seconds"),
    }

    try:
        enviar_para_fila(pedido)
    except Exception as erro:
        print(f"[A] request_id={request_id} erro ao publicar no rabbitmq: {erro}")
        return jsonify({"erro": "rabbitmq indisponivel"}), 503

    print(f"[A] request_id={request_id} pedido {pedido['id']} publicado na fila '{FILA}'")
    return jsonify({"status": "pedido enviado pra fila", "pedido": pedido}), 202


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
