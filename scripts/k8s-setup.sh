#!/usr/bin/env bash
# ETAPA 2 - sobe o cluster local (minikube), constroi as imagens e implanta tudo.
set -euo pipefail
cd "$(dirname "$0")/.."

# 1) credenciais: .env fica so na maquina, nunca no Git
if [[ ! -f .env ]]; then
  cp .env.example .env
  sed -i "s/^RABBITMQ_PASSWORD=.*/RABBITMQ_PASSWORD=$(openssl rand -hex 12)/" .env
  echo ">> .env criado com senha aleatoria"
fi
set -a; source .env; set +a

# 2) cluster
if ! minikube status >/dev/null 2>&1; then
  echo ">> iniciando minikube"
  minikube start --driver=docker --cpus="${MINIKUBE_CPUS:-$(nproc)}" --memory="${MINIKUBE_MEMORIA:-6144}"
fi
echo ">> habilitando NGINX Ingress Controller e metrics-server (necessario pro HPA)"
minikube addons enable ingress
minikube addons enable metrics-server

# 3) imagens construidas direto no Docker do minikube (sem registry externo)
echo ">> construindo imagens dentro do minikube"
eval "$(minikube docker-env)"
docker build -t pedidos/servico-a:1.0 ./servico-a
docker build -t pedidos/servico-b:1.0 ./servico-b
eval "$(minikube docker-env --unset)"

# 4) namespace + secret (gerado a partir do .env, nao fica salvo em arquivo)
kubectl apply -f k8s/00-namespace.yaml
kubectl -n pedidos create secret generic rabbitmq-credenciais \
  --from-literal=RABBITMQ_USER="$RABBITMQ_USER" \
  --from-literal=RABBITMQ_PASSWORD="$RABBITMQ_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# 5) espera o ingress controller (o webhook dele precisa estar pronto pra aceitar o Ingress)
echo ">> aguardando o ingress controller"
kubectl -n ingress-nginx wait --for=condition=ready pod \
  -l app.kubernetes.io/component=controller --timeout=300s

# 6) aplica os manifestos (a pasta k8s/hpa fica de fora de proposito: e da etapa 3)
kubectl apply -f k8s/

echo ">> aguardando os componentes ficarem prontos"
kubectl -n pedidos rollout status statefulset/rabbitmq --timeout=300s
kubectl -n pedidos rollout status deployment/servico-a --timeout=300s
kubectl -n pedidos rollout status deployment/servico-b --timeout=300s

echo
kubectl -n pedidos get pods,svc,ingress
echo
echo "Pronto. Rode ./scripts/k8s-acesso.sh para abrir o acesso pelo Ingress."
