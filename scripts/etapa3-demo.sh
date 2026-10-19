#!/bin/bash
# Demonstracao da ETAPA 3 (escalabilidade manual + HPA)
cd "$(dirname "$0")/.."
URL=http://localhost:8081
K="kubectl -n pedidos"

titulo() { echo; echo "======================================================"; echo " $1"; echo "======================================================"; }
pausa() { if [ -t 0 ]; then read -p "[enter para continuar]"; fi; }
cpu_atual() { $K get hpa servico-b -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}'; }
mensagens_na_fila() { $K exec rabbitmq-0 -- rabbitmqctl -q --no-table-headers list_queues name messages | awk '$1=="pedidos" {print $2}'; }

titulo "1) ESCALABILIDADE (manual): servico B de 2 para 4 replicas"
$K scale deployment servico-b --replicas=4
$K rollout status deployment/servico-b
$K get pods -l app=servico-b
pausa

titulo "2) Mandando 20 pedidos pra ver os 4 dividindo"
./scripts/gerar-carga.sh 20 $URL
sleep 10
echo "pedidos processados por pod:"
$K logs -l app=servico-b --since=20s | grep "processado" | grep -o "\[B [^]]*\]" | sort | uniq -c
pausa

titulo "3) Voltando pra 2 replicas"
$K scale deployment servico-b --replicas=2
$K get deployment servico-b
pausa

titulo "4) ELASTICIDADE (automatica): ligando o HPA"
kubectl apply -f k8s/hpa/servico-b-hpa.yaml
echo "esperando o metrics-server mandar a primeira medida de CPU..."
until [ -n "$(cpu_atual)" ]; do sleep 5; done
$K get hpa servico-b
pausa

titulo "5) Gerando carga: 300 pedidos"
./scripts/gerar-carga.sh 300 $URL
echo
echo "TEMPO   CPU (alvo 50%)   REPLICAS   NA FILA"
INICIO=$(date +%s)
FILA_ZEROU=0
while true; do
  T=$(( $(date +%s) - INICIO ))
  CPU=$(cpu_atual)
  REPLICAS=$($K get deployment servico-b -o jsonpath='{.status.readyReplicas}')
  FILA=$(mensagens_na_fila)
  echo "${T}s     ${CPU}%            ${REPLICAS:-0}          $FILA"
  if [ "$FILA" == "0" ]; then FILA_ZEROU=1; fi
  # para quando a fila esvaziou e o HPA voltou pra 1 replica (ou depois de 15 min)
  if [ $FILA_ZEROU == 1 ] && [ "$REPLICAS" == "1" ]; then break; fi
  if [ $T -gt 900 ]; then break; fi
  sleep 10
done
echo
$K describe hpa servico-b | sed -n '/Events:/,$p'

echo
echo "fim da etapa 3"
