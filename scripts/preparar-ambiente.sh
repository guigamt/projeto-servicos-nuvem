#!/usr/bin/env bash
# Roda uma vez quando o Codespace e criado: permissoes e .env com senha aleatoria.
set -euo pipefail
cd "$(dirname "$0")/.."
chmod +x scripts/*.sh
if [[ ! -f .env ]]; then
  cp .env.example .env
  sed -i "s/^RABBITMQ_PASSWORD=.*/RABBITMQ_PASSWORD=$(openssl rand -hex 12)/" .env
  echo ".env criado com senha aleatoria"
fi
