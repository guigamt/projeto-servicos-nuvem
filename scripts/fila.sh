#!/usr/bin/env bash
# Mostra o estado da fila direto no RabbitMQ.
# Uso: ./scripts/fila.sh            (Docker Compose)
#      ./scripts/fila.sh k8s        (Kubernetes)
set -euo pipefail
cd "$(dirname "$0")/.."

CMD=(rabbitmqctl -q list_queues name messages_ready messages_unacknowledged consumers)
if [[ "${1:-compose}" == "k8s" ]]; then
  kubectl -n pedidos exec rabbitmq-0 -- "${CMD[@]}"
else
  docker compose exec -T rabbitmq "${CMD[@]}"
fi
