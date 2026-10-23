#!/bin/bash
# prepara o ambiente: cria o .env com senha aleatoria e instala kubectl/minikube se nao tiver
# (roda sozinho quando o codespace e criado)
cd "$(dirname "$0")/.."
chmod +x scripts/*.sh

if [ ! -f .env ]; then
  cp .env.example .env
  sed -i "s/^RABBITMQ_PASSWORD=.*/RABBITMQ_PASSWORD=$(python3 -c "import secrets; print(secrets.token_hex(12))")/" .env
  echo ".env criado"
fi

# no github actions o minikube ja vem instalado por outro passo
if [ -z "$GITHUB_ACTIONS" ]; then
  if ! command -v kubectl > /dev/null; then
    echo "instalando kubectl..."
    curl -sLo /tmp/kubectl "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install /tmp/kubectl /usr/local/bin/kubectl
  fi
  if ! command -v minikube > /dev/null; then
    echo "instalando minikube..."
    curl -sLo /tmp/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install /tmp/minikube /usr/local/bin/minikube
  fi
fi
