#!/bin/bash
# cria o .env com uma senha aleatoria (roda sozinho quando o codespace e criado)
cd "$(dirname "$0")/.."
chmod +x scripts/*.sh
if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s/^RABBITMQ_PASSWORD=.*/RABBITMQ_PASSWORD=$(openssl rand -hex 12)/" .env
  echo ".env criado"
fi
