#!/bin/bash
# Demonstracao da ETAPA 1 (Docker Compose)
# antes: docker compose up -d --build
cd "$(dirname "$0")/.."
URL=http://localhost:8080

titulo() { echo; echo "======================================================"; echo " $1"; echo "======================================================"; }
pausa() { if [ -t 0 ]; then read -p "[enter para continuar]"; fi; }

titulo "1) Containers rodando - so o nginx tem porta aberta (8080)"
docker compose ps --format "table {{.Service}}\t{{.State}}\t{{.Ports}}"
pausa

titulo "2) Tentando acessar o servico A direto (tem que dar erro)"
curl -s -m 3 http://localhost:5000/health || echo "nao conectou -> o servico A nao esta exposto"
pausa

titulo "3) Fazendo um pedido pelo nginx"
RESPOSTA=$(curl -s -X POST $URL/pedidos -H "Content-Type: application/json" \
  -d '{"cliente":"maria","produto":"camiseta","quantidade":2}')
echo "$RESPOSTA"
ID=$(echo "$RESPOSTA" | python3 -c "import sys,json; print(json.load(sys.stdin)['pedido']['request_id'])")
sleep 3
pausa

titulo "4) Seguindo o request_id=$ID nos logs (nginx -> A -> B)"
docker compose logs --no-log-prefix nginx servico-a servico-b | grep "$ID"
pausa

titulo "5) O servico A nao conhece o servico B (variaveis do A)"
docker compose exec -T servico-a env | grep RABBITMQ_HOST
echo "-> o A so sabe onde esta o rabbitmq, nao tem nada do servico B"
pausa

titulo "6) FALHA: parando o servico B"
docker compose stop servico-b
./scripts/fila.sh
pausa

titulo "7) Fazendo 10 pedidos com o servico B parado"
./scripts/gerar-carga.sh 10 $URL
sleep 2
echo "-> o A continuou recebendo. Os pedidos ficaram esperando na fila:"
./scripts/fila.sh
pausa

titulo "8) Ligando o servico B de novo"
docker compose start servico-b
sleep 15
docker compose logs --since 20s servico-b
echo
./scripts/fila.sh
echo "-> os 10 pedidos que estavam na fila foram processados"
pausa

titulo "9) Extra: 3 servicos B dividindo os pedidos"
docker compose up -d --scale servico-b=3 --no-recreate servico-b
sleep 5
./scripts/gerar-carga.sh 12 $URL
sleep 8
echo "pedidos processados por cada container:"
docker compose logs --since 15s servico-b | grep "processado" | grep -o "\[B [^]]*\]" | sort | uniq -c
docker compose up -d --scale servico-b=1 --no-recreate servico-b

echo
echo "fim da etapa 1"
