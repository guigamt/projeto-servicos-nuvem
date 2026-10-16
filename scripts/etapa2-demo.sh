#!/usr/bin/env bash
# Roteiro da demonstracao da ETAPA 2 (Kubernetes).
# Pressupoe: ./scripts/k8s-setup.sh e ./scripts/k8s-acesso.sh ja executados.
set -uo pipefail
cd "$(dirname "$0")/.."
URL="${URL:-http://localhost:8081}"
K="kubectl -n pedidos"

titulo() { echo; echo "=================================================================="; echo "  $1"; echo "=================================================================="; }
pausa()  { echo; read -rp "[Enter para continuar] " _; }

titulo "1) O que esta rodando no cluster"
$K get deploy,statefulset,pods -o wide
echo
$K get svc,ingress
echo ">> todos os Services sao ClusterIP (internos). So o Ingress recebe trafego de fora."
pausa

titulo "2) Pedido pelo Ingress + rastreio nos logs"
RESP=$(curl -sS -X POST "$URL/api/pedidos" -H 'Content-Type: application/json' \
  -d '{"cliente":"demo-k8s","itens":[{"produto":"mochila","quantidade":1}]}')
echo "$RESP" | python3 -m json.tool
RID=$(echo "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["request_id"])')
sleep 3
echo; echo "--- Ingress controller ---"
kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=200 | grep "$RID" || true
echo "--- Servico A ---"
$K logs -l app=servico-a --prefix --tail=200 | grep "$RID" || true
echo "--- Servico B ---"
$K logs -l app=servico-b --prefix --tail=200 | grep "$RID" || true
pausa

titulo "3) SELF-HEALING: removendo manualmente um pod do Servico B"
$K get pods -l app=servico-b
ALVO=$($K get pods -l app=servico-b -o jsonpath='{.items[0].metadata.name}')
echo; echo ">> kubectl delete pod $ALVO"
$K delete pod "$ALVO" --wait=false
for i in $(seq 1 8); do
  sleep 3
  echo "--- t=$((i*3))s ---"
  $K get pods -l app=servico-b --no-headers
done
echo
$K get deploy servico-b
echo ">> o Deployment percebeu que tinha menos replicas que o desejado e criou outro pod."
pausa

titulo "4) Service estavel: derrubando um pod do Servico A com trafego chegando"
ALVO=$($K get pods -l app=servico-a -o jsonpath='{.items[0].metadata.name}')
$K delete pod "$ALVO" --wait=false
for i in $(seq 1 10); do
  curl -sS -o /dev/null -w "requisicao $i -> HTTP %{http_code}\n" "$URL/api/fila"
  sleep 1
done
$K get pods -l app=servico-a
pausa

titulo "5) Persistencia do RabbitMQ: mensagens sobrevivem ao restart do broker"
echo ">> zerando consumidores (servico-b replicas=0) para acumular mensagens"
$K scale deploy servico-b --replicas=0
sleep 5
./scripts/gerar-carga.sh 5 "$URL"
./scripts/fila.sh k8s
echo; echo ">> apagando o pod rabbitmq-0 (o volume persistente continua)"
$K delete pod rabbitmq-0
$K rollout status statefulset/rabbitmq --timeout=300s
sleep 5
./scripts/fila.sh k8s
echo ">> as 5 mensagens continuam la (fila duravel + mensagens persistentes + PVC)"
echo; echo ">> voltando o servico-b para 2 replicas"
$K scale deploy servico-b --replicas=2
$K rollout status deploy/servico-b --timeout=120s
sleep 8
./scripts/fila.sh k8s
echo
echo "Fim da demonstracao da etapa 2."
