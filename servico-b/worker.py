"""
Servico B - processador de pedidos (consumidor / worker).

Consome mensagens da fila 'pedidos' no RabbitMQ e "processa" cada pedido.
O processamento gasta CPU de proposito (PROCESSAMENTO_MS) para que o HPA
do Kubernetes consiga perceber o aumento de carga.

Nao conhece o Servico A e nao abre nenhuma porta: so se conecta ao broker.
"""

import hashlib
import json
import logging
import os
import signal
import time
from pathlib import Path

import pika
from pika.exceptions import AMQPError

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.environ.get("RABBITMQ_USER", "")
RABBITMQ_PASSWORD = os.environ.get("RABBITMQ_PASSWORD", "")
FILA = os.getenv("FILA_PEDIDOS", "pedidos")
PROCESSAMENTO_MS = int(os.getenv("PROCESSAMENTO_MS", "300"))
PREFETCH = int(os.getenv("PREFETCH", "1"))
INSTANCIA = os.getenv("HOSTNAME", "servico-b")
ARQUIVO_VIVO = Path(os.getenv("ARQUIVO_VIVO", "/tmp/vivo"))

logging.basicConfig(
    level=logging.INFO,
    format=f"%(asctime)s [servico-b {INSTANCIA}] %(levelname)s %(message)s",
)
log = logging.getLogger("servico-b")
logging.getLogger("pika").setLevel(logging.WARNING)

parar = False
processados = 0


def pedir_parada(sinal, _frame):
    # SIGTERM chega quando o container/pod e parado. Termina a mensagem atual,
    # da ack e sai. O que nao foi confirmado volta para a fila.
    global parar
    log.info("sinal %s recebido, encerrando depois da mensagem atual", signal.Signals(sinal).name)
    parar = True


signal.signal(signal.SIGTERM, pedir_parada)
signal.signal(signal.SIGINT, pedir_parada)


def marcar_vivo() -> None:
    # usado pela livenessProbe do Kubernetes
    ARQUIVO_VIVO.touch()


def trabalho_de_cpu(ms: int) -> str:
    """Simula um processamento pesado (calculo de frete, nota fiscal, etc.)
    ocupando a CPU por aproximadamente 'ms' milissegundos."""
    fim = time.perf_counter() + ms / 1000
    h = b"pedido"
    while time.perf_counter() < fim:
        h = hashlib.sha256(h).digest()
    return h.hex()[:12]


def processar(canal, metodo, propriedades, corpo) -> None:
    global processados
    inicio = time.perf_counter()
    try:
        pedido = json.loads(corpo)
        rid = pedido["request_id"]
        pid = pedido["pedido_id"]
    except (ValueError, KeyError) as erro:
        # mensagem fora do contrato: descarta para nao travar a fila
        log.error("mensagem invalida descartada (%s): %r", erro, corpo[:200])
        canal.basic_nack(delivery_tag=metodo.delivery_tag, requeue=False)
        return

    log.info(
        "request_id=%s pedido_id=%s recebido (cliente=%s, itens=%s, reentrega=%s)",
        rid, pid, pedido.get("cliente"), pedido.get("total_itens"), metodo.redelivered,
    )
    codigo = trabalho_de_cpu(PROCESSAMENTO_MS)
    canal.basic_ack(delivery_tag=metodo.delivery_tag)  # so confirma depois de processar
    processados += 1
    log.info(
        "request_id=%s pedido_id=%s processado em %.0f ms (codigo=%s, total nesta instancia=%s)",
        rid, pid, (time.perf_counter() - inicio) * 1000, codigo, processados,
    )


def consumir() -> None:
    credenciais = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
    parametros = pika.ConnectionParameters(
        host=RABBITMQ_HOST,
        port=RABBITMQ_PORT,
        credentials=credenciais,
        heartbeat=30,
        client_properties={"connection_name": INSTANCIA},
    )
    conexao = pika.BlockingConnection(parametros)
    canal = conexao.channel()
    canal.queue_declare(queue=FILA, durable=True)
    # prefetch=1: cada worker pega uma mensagem por vez -> distribuicao justa
    canal.basic_qos(prefetch_count=PREFETCH)
    log.info("conectado ao RabbitMQ, consumindo fila '%s' (processamento ~%s ms por pedido)", FILA, PROCESSAMENTO_MS)

    try:
        for metodo, propriedades, corpo in canal.consume(FILA, inactivity_timeout=1):
            marcar_vivo()
            if parar:
                break
            if metodo is None:  # passou 1s sem mensagem
                continue
            processar(canal, metodo, propriedades, corpo)
    finally:
        if canal.is_open:
            devolvidas = canal.cancel()  # mensagens nao confirmadas voltam pra fila
            if devolvidas:
                log.info("%s mensagem(ns) nao processada(s) devolvida(s) para a fila", devolvidas)
        if conexao.is_open:
            conexao.close()


def main() -> None:
    espera = 1
    marcar_vivo()
    while not parar:
        try:
            consumir()
            espera = 1
        except AMQPError as erro:
            if parar:
                break
            log.warning("conexao com RabbitMQ indisponivel (%s). Nova tentativa em %ss", erro.__class__.__name__, espera)
            # dorme em passos de 1s para continuar respondendo a liveness e ao SIGTERM
            for _ in range(espera):
                if parar:
                    break
                marcar_vivo()
                time.sleep(1)
            espera = min(espera * 2, 10)
    log.info("servico-b encerrado. Pedidos processados nesta instancia: %s", processados)


if __name__ == "__main__":
    main()
