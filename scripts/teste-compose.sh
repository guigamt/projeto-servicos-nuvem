#!/usr/bin/env bash
# Teste automatico (sem pausas) da etapa 1. Usado no GitHub Actions.
set -euo pipefail
cd "$(dirname "$0")/.."
URL=http://localhost:8080
falha() { echo "FALHOU: $1"; docker compose logs --tail=80; exit 1; }
na_fila() { docker compose exec -T rabbitmq rabbitmqctl -q --no-table-headers list_queues name messages | awk '$1=="pedidos"{print $2}'; }

[[ -f .env ]] || bash scripts/preparar-ambiente.sh
docker compose up -d --build --wait

echo "== pedido pelo NGINX"
RESP=$(curl -sSf -X POST $URL/api/pedidos -H 'Content-Type: application/json' \
  -d '{"cliente":"ci","itens":[{"produto":"caneca","quantidade":1}]}')
echo "$RESP"
RID=$(echo "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["request_id"])')
sleep 3
docker compose logs nginx | grep -q "$RID" || falha "request_id nao aparece no NGINX"
docker compose logs servico-a | grep -q "$RID" || falha "request_id nao aparece no Servico A"
docker compose logs servico-b | grep "$RID" | grep -q "processado" || falha "Servico B nao processou"

echo "== Servico A nao acessivel direto"
curl -s -m 3 http://localhost:8000 && falha "porta 8000 nao deveria responder" || true

echo "== falha controlada do consumidor"
docker compose stop servico-b
for i in $(seq 1 10); do
  curl -sSf -o /dev/null -X POST $URL/api/pedidos -H 'Content-Type: application/json' \
    -d '{"cliente":"ci","itens":[{"produto":"caneca","quantidade":1}]}'
done
sleep 2
[[ "$(na_fila)" == "10" ]] || falha "esperava 10 mensagens na fila, tem $(na_fila)"
docker compose start servico-b
for i in $(seq 1 30); do [[ "$(na_fila)" == "0" ]] && break; sleep 2; done
[[ "$(na_fila)" == "0" ]] || falha "fila nao esvaziou depois de religar o Servico B"

echo "== restart do RabbitMQ preserva mensagens"
docker compose stop servico-b
curl -sSf -o /dev/null -X POST $URL/api/pedidos/lote -H 'Content-Type: application/json' -d '{"quantidade":7}'
docker compose restart rabbitmq
sleep 15
[[ "$(na_fila)" == "7" ]] || falha "mensagens se perderam no restart do broker ($(na_fila))"
docker compose start servico-b
for i in $(seq 1 30); do [[ "$(na_fila)" == "0" ]] && break; sleep 2; done
[[ "$(na_fila)" == "0" ]] || falha "fila nao esvaziou"
curl -sSf -X POST $URL/api/pedidos -H 'Content-Type: application/json' \
  -d '{"cliente":"ci","itens":[{"produto":"caneca","quantidade":1}]}' >/dev/null || falha "Servico A nao reconectou ao broker"

echo "ETAPA 1 OK"
