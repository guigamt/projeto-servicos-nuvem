#!/bin/bash
# Demonstracao da ETAPA 2 (Kubernetes)
# antes: ./scripts/k8s-setup.sh e ./scripts/k8s-acesso.sh
cd "$(dirname "$0")/.."
URL=http://localhost:8081
K="kubectl -n pedidos"

titulo() { echo; echo "======================================================"; echo " $1"; echo "======================================================"; }
pausa() { if [ -t 0 ]; then read -p "[enter para continuar]"; fi; }

titulo "1) O que esta rodando no cluster"
$K get deployments,statefulsets,pods
echo
$K get services,ingress
echo "-> todos os services sao ClusterIP (internos). A entrada e o Ingress"
pausa

titulo "2) Pedido pelo Ingress e seguindo nos logs"
RESPOSTA=$(curl -s -X POST $URL/pedidos -H "Content-Type: application/json" \
  -d '{"cliente":"joao","produto":"mochila","quantidade":1}')
echo "$RESPOSTA"
ID=$(echo "$RESPOSTA" | python3 -c "import sys,json; print(json.load(sys.stdin)['pedido']['request_id'])")
sleep 3
echo "--- ingress ---"
kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=100 | grep "$ID"
echo "--- servico A ---"
$K logs -l app=servico-a --tail=100 | grep "$ID"
echo "--- servico B ---"
$K logs -l app=servico-b --tail=100 | grep "$ID"
pausa

titulo "3) SELF-HEALING: apagando um pod do servico B"
$K get pods -l app=servico-b
POD=$($K get pods -l app=servico-b -o jsonpath='{.items[0].metadata.name}')
echo
echo "kubectl delete pod $POD"
$K delete pod $POD --wait=false
for i in 1 2 3 4 5 6; do
  sleep 3
  echo "--- depois de $((i*3))s ---"
  $K get pods -l app=servico-b
done
$K get deployment servico-b
echo "-> o deployment quer 2 replicas, viu que tinha 1 e criou outro pod sozinho"
pausa

titulo "4) RabbitMQ com volume: as mensagens sobrevivem se o pod do rabbit cair"
$K scale deployment servico-b --replicas=0
sleep 5
./scripts/gerar-carga.sh 5 $URL
./scripts/fila.sh k8s
echo
echo "apagando o pod rabbitmq-0..."
$K delete pod rabbitmq-0
$K rollout status statefulset/rabbitmq --timeout=300s
sleep 5
./scripts/fila.sh k8s
echo "-> as 5 mensagens continuam la (fila duravel + mensagem persistente + volume)"
$K scale deployment servico-b --replicas=2
$K rollout status deployment/servico-b
sleep 10
./scripts/fila.sh k8s

echo
echo "fim da etapa 2"
