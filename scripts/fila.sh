#!/bin/bash
# mostra quantas mensagens tem na fila e quantos consumidores estao ligados
# uso: ./scripts/fila.sh        (docker compose)
#      ./scripts/fila.sh k8s    (kubernetes)
if [ "$1" == "k8s" ]; then
  kubectl -n pedidos exec rabbitmq-0 -- rabbitmqctl -q list_queues name messages consumers
else
  docker compose exec -T rabbitmq rabbitmqctl -q list_queues name messages consumers
fi
