#!/usr/bin/env bash
# Teste automatico (sem pausas) das etapas 2 e 3. Usado no GitHub Actions.
set -euo pipefail
cd "$(dirname "$0")/.."
URL=http://localhost:8081
K="kubectl -n pedidos"
falha() { echo "FALHOU: $1"; $K get all; $K describe hpa servico-b || true; $K logs -l app=servico-b --tail=30 --prefix || true; exit 1; }
na_fila() { $K exec rabbitmq-0 -- rabbitmqctl -q --no-table-headers list_queues name messages | awk '$1=="pedidos"{print $2}'; }

bash scripts/k8s-setup.sh
bash scripts/k8s-acesso.sh

echo "== pedido pelo Ingress"
curl -sSf -X POST $URL/api/pedidos -H 'Content-Type: application/json' \
  -d '{"cliente":"ci","itens":[{"produto":"boné","quantidade":1}]}'
echo

echo "== self-healing"
ALVO=$($K get pods -l app=servico-b -o jsonpath='{.items[0].metadata.name}')
$K delete pod "$ALVO" --wait=false
sleep 5
$K rollout status deploy/servico-b --timeout=120s
[[ "$($K get deploy servico-b -o jsonpath='{.status.readyReplicas}')" == "2" ]] || falha "self-healing"

echo "== escala manual"
$K scale deploy servico-b --replicas=4
$K rollout status deploy/servico-b --timeout=180s
$K scale deploy servico-b --replicas=2

echo "== HPA"
kubectl apply -f k8s/hpa/servico-b-hpa.yaml
for i in $(seq 1 36); do
  CPU=$($K get hpa servico-b -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)
  [[ -n "$CPU" ]] && break; sleep 5
done
[[ -n "${CPU:-}" ]] || falha "HPA sem metrica de CPU (metrics-server?)"
bash scripts/gerar-carga.sh 1500 $URL
MAX=0
for i in $(seq 1 40); do
  REP=$($K get deploy servico-b -o jsonpath='{.status.replicas}')
  (( REP > MAX )) && MAX=$REP
  echo "t=$((i*10))s replicas=$REP cpu=$($K get hpa servico-b -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}')% fila=$(na_fila)"
  (( MAX >= 3 )) && break
  sleep 10
done
(( MAX >= 3 )) || falha "HPA nao escalou (max=$MAX)"
$K get hpa servico-b
echo "ETAPAS 2 e 3 OK"
