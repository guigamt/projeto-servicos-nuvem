#!/usr/bin/env bash
# Roteiro da demonstracao da ETAPA 1 (Docker Compose).
# Pressupoe que a aplicacao ja esta no ar: docker compose up -d --build
set -uo pipefail
cd "$(dirname "$0")/.."
URL="${URL:-http://localhost:8080}"

titulo() { echo; echo "=================================================================="; echo "  $1"; echo "=================================================================="; }
pausa()  { echo; read -rp "[Enter para continuar] " _; }

titulo "1) Containers e portas: so o NGINX publica porta para o host"
docker compose ps --format 'table {{.Service}}\t{{.State}}\t{{.Ports}}'
pausa

titulo "2) Tentando acessar o Servico A direto (deve FALHAR)"
curl -sS -m 3 http://localhost:8000/api/health/live || echo ">> sem acesso: o Servico A nao tem porta publicada"
pausa

titulo "3) Criando um pedido pelo ponto de entrada (NGINX)"
RESP=$(curl -sS -X POST "$URL/api/pedidos" -H 'Content-Type: application/json' \
  -d '{"cliente":"demo","itens":[{"produto":"camiseta","quantidade":2}]}')
echo "$RESP" | python3 -m json.tool
RID=$(echo "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["request_id"])')
sleep 2
pausa

titulo "4) Seguindo o request_id=$RID pelos logs de todos os componentes"
docker compose logs --no-log-prefix nginx servico-a servico-b 2>/dev/null | grep "$RID" || true
pausa

titulo "5) Servico A nao conhece o Servico B (variaveis de ambiente do A)"
docker compose exec -T servico-a env | grep -E 'RABBITMQ_HOST|FILA' 
echo ">> nenhuma referencia ao servico-b: o A so conhece o broker e o nome da fila"
pausa

titulo "6) FALHA CONTROLADA: parando o Servico B"
docker compose stop servico-b
./scripts/fila.sh
pausa

titulo "7) Criando 10 pedidos com o consumidor parado"
for i in $(seq 1 10); do
  curl -sS -o /dev/null -w "pedido $i -> HTTP %{http_code}\n" -X POST "$URL/api/pedidos" \
    -H 'Content-Type: application/json' -d "{\"cliente\":\"falha-$i\",\"itens\":[{\"produto\":\"caneca\",\"quantidade\":1}]}"
done
echo ">> o Servico A continuou aceitando os pedidos. Estado da fila:"
./scripts/fila.sh
pausa

titulo "8) Religando o Servico B: mensagens pendentes sao processadas"
docker compose start servico-b
sleep 8
docker compose logs --since 15s servico-b
echo
./scripts/fila.sh
pausa

titulo "9) Extra: 3 consumidores dividindo a fila"
docker compose up -d --scale servico-b=3 --no-recreate servico-b
sleep 5
./scripts/gerar-carga.sh 30 "$URL"
sleep 10
echo ">> pedidos processados por instancia:"
docker compose logs --since 20s servico-b 2>/dev/null | grep "processado em" | awk '{print $1}' | sort | uniq -c
docker compose up -d --scale servico-b=1 --no-recreate servico-b
echo
echo "Fim da demonstracao da etapa 1."
