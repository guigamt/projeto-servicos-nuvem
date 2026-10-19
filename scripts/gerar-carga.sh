#!/bin/bash
# manda varios pedidos de uma vez (10 em paralelo) pra gerar carga
# uso: ./scripts/gerar-carga.sh [quantidade] [url]
QTD=${1:-10}
URL=${2:-http://localhost:8080}

echo "enviando $QTD pedidos para $URL ..."
seq 1 $QTD | xargs -P 10 -I{} curl -s -o /dev/null -X POST "$URL/pedidos" \
  -H "Content-Type: application/json" \
  -d '{"cliente":"cliente-{}","produto":"caneca","quantidade":1}'
echo "pronto, $QTD pedidos enviados"
