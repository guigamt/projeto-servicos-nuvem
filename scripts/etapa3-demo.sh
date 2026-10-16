#!/usr/bin/env bash
# Roteiro da demonstracao da ETAPA 3 (escalabilidade manual + HPA).
set -uo pipefail
cd "$(dirname "$0")/.."
URL="${URL:-http://localhost:8081}"
K="kubectl -n pedidos"
CARGA="${CARGA:-1500}"

titulo() { echo; echo "=================================================================="; echo "  $1"; echo "=================================================================="; }
pausa()  { echo; read -rp "[Enter para continuar] " _; }
na_fila() { $K exec rabbitmq-0 -- rabbitmqctl -q --no-table-headers list_queues name messages 2>/dev/null | awk '$1=="pedidos"{print $2}'; }

titulo "1) ESCALABILIDADE MANUAL: Servico B de 2 para 4 replicas"
$K scale deploy servico-b --replicas=4
$K rollout status deploy/servico-b --timeout=120s
$K get pods -l app=servico-b
sleep 5
./scripts/fila.sh k8s
pausa

titulo "2) 4 consumidores dividindo a fila"
./scripts/gerar-carga.sh 80 "$URL"
sleep 15
echo ">> pedidos processados por pod nos ultimos 20s:"
$K logs -l app=servico-b --prefix --since=20s --tail=-1 | grep "processado em" | awk '{print $1}' | sort | uniq -c
pausa

titulo "3) Voltando para 2 replicas (ainda manual)"
$K scale deploy servico-b --replicas=2
$K get deploy servico-b
pausa

titulo "4) ELASTICIDADE: aplicando o HorizontalPodAutoscaler"
kubectl apply -f k8s/hpa/servico-b-hpa.yaml
echo ">> aguardando o metrics-server entregar a primeira leitura de CPU..."
for i in $(seq 1 30); do
  CPU=$($K get hpa servico-b -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
  [[ -n "$CPU" ]] && break
  sleep 5
done
$K get hpa servico-b
echo ">> sem carga, o HPA tende a descer para o minimo (1 replica)."
pausa

titulo "5) Gerando carga artificial: $CARGA pedidos"
./scripts/gerar-carga.sh "$CARGA" "$URL"
echo
printf "%-10s %-10s %-10s %-12s\n" "TEMPO" "CPU(%)" "REPLICAS" "NA FILA"
INICIO=$(date +%s)
ZERADA=0
while true; do
  T=$(( $(date +%s) - INICIO ))
  CPU=$($K get hpa servico-b -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
  REP=$($K get deploy servico-b -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  FILA=$(na_fila)
  printf "%-10s %-10s %-10s %-12s\n" "${T}s" "${CPU:-?}" "${REP:-0}" "${FILA:-?}"
  [[ "${FILA:-1}" == "0" ]] && ZERADA=1
  # termina quando a fila esvaziou e o HPA voltou para 1 replica (ou depois de 20 min)
  if [[ $ZERADA == 1 && "${REP:-0}" == "1" ]] || (( T > 1200 )); then break; fi
  sleep 10
done
echo
$K describe hpa servico-b | sed -n '/Events:/,$p'
echo
echo "Fim da demonstracao da etapa 3."
