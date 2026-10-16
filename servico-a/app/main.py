"""
Servico A - API de pedidos (produtor).

Recebe pedidos via HTTP (sempre atras do NGINX / Ingress), monta a mensagem
e publica na fila do RabbitMQ. Nao conhece o Servico B: so conhece o broker
e o formato da mensagem.
"""

import asyncio
import json
import logging
import os
import random
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import aio_pika
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Configuracao (tudo via variavel de ambiente, nada de senha no codigo)
# ---------------------------------------------------------------------------
RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.environ.get("RABBITMQ_USER", "")
RABBITMQ_PASSWORD = os.environ.get("RABBITMQ_PASSWORD", "")
FILA = os.getenv("FILA_PEDIDOS", "pedidos")
INSTANCIA = os.getenv("HOSTNAME", "servico-a")

logging.basicConfig(
    level=logging.INFO,
    format=f"%(asctime)s [servico-a {INSTANCIA}] %(levelname)s %(message)s",
)
log = logging.getLogger("servico-a")
logging.getLogger("aio_pika").setLevel(logging.WARNING)
logging.getLogger("aiormq").setLevel(logging.WARNING)

PRODUTOS = ["camiseta", "caneca", "mochila", "boné", "garrafa", "caderno", "adesivo"]
CLIENTES = ["ana", "bruno", "carla", "diego", "eduarda", "felipe", "gabi", "heitor"]


# ---------------------------------------------------------------------------
# Modelos de entrada
# ---------------------------------------------------------------------------
class Item(BaseModel):
    produto: str = Field(min_length=1, max_length=60)
    quantidade: int = Field(ge=1, le=100)


class PedidoIn(BaseModel):
    cliente: str = Field(min_length=1, max_length=80)
    itens: list[Item] = Field(min_length=1, max_length=20)


class LoteIn(BaseModel):
    quantidade: int = Field(default=100, ge=1, le=5000)


# ---------------------------------------------------------------------------
# Conexao com o RabbitMQ
# ---------------------------------------------------------------------------
class Broker:
    def __init__(self) -> None:
        self.conexao: aio_pika.abc.AbstractRobustConnection | None = None
        self.canal: aio_pika.abc.AbstractRobustChannel | None = None

    @property
    def pronto(self) -> bool:
        return (
            self.conexao is not None
            and not self.conexao.is_closed
            and self.canal is not None
            and not self.canal.is_closed
        )

    async def conectar(self) -> None:
        """Tenta conectar ate conseguir. Roda em background para a API subir
        mesmo que o broker ainda nao esteja pronto (readiness fica 503)."""
        espera = 1
        url = f"amqp://{RABBITMQ_USER}:{RABBITMQ_PASSWORD}@{RABBITMQ_HOST}:{RABBITMQ_PORT}/"
        while True:
            try:
                self.conexao = await aio_pika.connect_robust(url, client_properties={"connection_name": INSTANCIA})
                # publisher_confirms: o publish so retorna depois que o broker confirmou
                self.canal = await self.conexao.channel(publisher_confirms=True)
                # fila duravel: sobrevive a restart do RabbitMQ
                await self.canal.declare_queue(FILA, durable=True)
                log.info("conectado ao RabbitMQ em %s:%s, fila '%s' declarada", RABBITMQ_HOST, RABBITMQ_PORT, FILA)
                return
            except Exception as erro:  # noqa: BLE001
                log.warning("RabbitMQ indisponivel (%s). Nova tentativa em %ss", erro.__class__.__name__, espera)
                await asyncio.sleep(espera)
                espera = min(espera * 2, 10)

    async def publicar(self, mensagem: dict) -> None:
        if not self.pronto:
            raise HTTPException(status_code=503, detail="broker indisponivel no momento")
        corpo = json.dumps(mensagem, ensure_ascii=False).encode("utf-8")
        await self.canal.default_exchange.publish(
            aio_pika.Message(
                body=corpo,
                content_type="application/json",
                delivery_mode=aio_pika.DeliveryMode.PERSISTENT,  # mensagem gravada em disco
                message_id=mensagem["pedido_id"],
                correlation_id=mensagem["request_id"],
                app_id="servico-a",
            ),
            routing_key=FILA,
        )

    async def estado_fila(self) -> dict:
        if not self.pronto:
            raise HTTPException(status_code=503, detail="broker indisponivel no momento")
        fila = await self.canal.declare_queue(FILA, passive=True)
        return {
            "fila": FILA,
            "mensagens_aguardando": fila.declaration_result.message_count,
            "consumidores": fila.declaration_result.consumer_count,
        }

    async def fechar(self) -> None:
        if self.conexao is not None:
            await self.conexao.close()


broker = Broker()


@asynccontextmanager
async def ciclo_de_vida(_: FastAPI):
    tarefa = asyncio.create_task(broker.conectar())
    yield
    tarefa.cancel()
    await broker.fechar()


app = FastAPI(title="Servico A - Pedidos", lifespan=ciclo_de_vida)
STATIC = Path(__file__).parent / "static"


def agora() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def request_id_de(request: Request) -> str:
    # O NGINX (e o ingress-nginx) mandam o X-Request-ID. Se nao vier, gera um.
    return request.headers.get("x-request-id") or uuid.uuid4().hex


def montar_mensagem(request_id: str, cliente: str, itens: list[dict]) -> dict:
    return {
        "versao": 1,
        "tipo": "pedido.criado",
        "pedido_id": str(uuid.uuid4()),
        "request_id": request_id,
        "cliente": cliente,
        "itens": itens,
        "total_itens": sum(i["quantidade"] for i in itens),
        "criado_em": agora(),
        "origem": INSTANCIA,
    }


# ---------------------------------------------------------------------------
# Rotas
# ---------------------------------------------------------------------------
@app.get("/", include_in_schema=False)
async def pagina_inicial():
    return FileResponse(STATIC / "index.html")


@app.get("/api/health/live")
async def vivo():
    # processo de pe -> livenessProbe
    return {"status": "vivo", "instancia": INSTANCIA}


@app.get("/api/health/ready")
async def pronto():
    # so recebe trafego se estiver conectado ao broker -> readinessProbe
    if not broker.pronto:
        return JSONResponse(status_code=503, content={"status": "sem broker", "instancia": INSTANCIA})
    return {"status": "pronto", "instancia": INSTANCIA}


@app.post("/api/pedidos", status_code=202)
async def criar_pedido(pedido: PedidoIn, request: Request):
    rid = request_id_de(request)
    log.info("request_id=%s requisicao recebida: novo pedido do cliente '%s'", rid, pedido.cliente)
    msg = montar_mensagem(rid, pedido.cliente, [i.model_dump() for i in pedido.itens])
    await broker.publicar(msg)
    log.info("request_id=%s pedido_id=%s publicado na fila '%s'", rid, msg["pedido_id"], FILA)
    return {"status": "enfileirado", "pedido_id": msg["pedido_id"], "request_id": rid, "atendido_por": INSTANCIA}


@app.post("/api/pedidos/lote", status_code=202)
async def criar_lote(lote: LoteIn, request: Request):
    """Gera varios pedidos aleatorios de uma vez. Usado para produzir carga
    no experimento de escalabilidade/elasticidade."""
    rid = request_id_de(request)
    log.info("request_id=%s requisicao recebida: lote de %s pedidos", rid, lote.quantidade)
    mensagens = []
    for n in range(lote.quantidade):
        itens = [
            {"produto": random.choice(PRODUTOS), "quantidade": random.randint(1, 5)}
            for _ in range(random.randint(1, 3))
        ]
        mensagens.append(montar_mensagem(f"{rid}.{n + 1}", random.choice(CLIENTES), itens))

    # publica em blocos para nao abrir milhares de confirmacoes ao mesmo tempo
    for inicio in range(0, len(mensagens), 200):
        await asyncio.gather(*(broker.publicar(m) for m in mensagens[inicio:inicio + 200]))

    log.info("request_id=%s %s pedidos publicados na fila '%s'", rid, len(mensagens), FILA)
    return {"status": "enfileirado", "quantidade": len(mensagens), "request_id": rid, "atendido_por": INSTANCIA}


@app.get("/api/fila")
async def fila():
    estado = await broker.estado_fila()
    estado["consultado_por"] = INSTANCIA
    return estado
