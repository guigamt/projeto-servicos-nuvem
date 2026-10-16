#!/usr/bin/env bash
# Gera N pedidos de uma vez pelo ponto de entrada (NGINX / Ingress).
# Uso: ./scripts/gerar-carga.sh [quantidade] [url]
set -euo pipefail
QTD="${1:-500}"
URL="${2:-http://localhost:8080}"
echo ">> enviando lote de $QTD pedidos para $URL"
curl -sS -X POST "$URL/api/pedidos/lote" \
  -H 'Content-Type: application/json' \
  -d "{\"quantidade\": $QTD}"
echo
