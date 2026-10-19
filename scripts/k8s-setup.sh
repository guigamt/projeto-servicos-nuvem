#!/bin/bash
# ETAPA 2 - sobe o minikube, builda as imagens e aplica os manifestos
set -e
cd "$(dirname "$0")/.."

# senha vem do .env (que nao vai pro git)
bash scripts/preparar-ambiente.sh
source .env

# 1) cluster
minikube status > /dev/null 2>&1 || minikube start --driver=docker --cpus=max --memory=6000
minikube addons enable ingress          # NGINX Ingress Controller
minikube addons enable metrics-server   # precisa pro HPA ler a CPU dos pods

# 2) imagens (builda local e joga dentro do minikube, sem precisar de registry)
docker build -t pedidos/servico-a:1.0 ./servico-a
docker build -t pedidos/servico-b:1.0 ./servico-b
minikube image load pedidos/servico-a:1.0 --overwrite=true
minikube image load pedidos/servico-b:1.0 --overwrite=true

# 3) namespace e secret com a senha
kubectl apply -f k8s/00-namespace.yaml
kubectl -n pedidos create secret generic rabbitmq-credenciais \
  --from-literal=RABBITMQ_USER="$RABBITMQ_USER" \
  --from-literal=RABBITMQ_PASSWORD="$RABBITMQ_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# 4) espera o ingress controller ficar pronto
echo "esperando o ingress controller..."
until kubectl -n ingress-nginx get pods -l app.kubernetes.io/component=controller 2>/dev/null | grep -q controller; do sleep 5; done
kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=300s

# 5) aplica os manifestos (a pasta hpa fica de fora, e da etapa 3)
kubectl apply -f k8s/
kubectl -n pedidos rollout status statefulset/rabbitmq --timeout=300s
kubectl -n pedidos rollout status deployment/servico-a --timeout=300s
kubectl -n pedidos rollout status deployment/servico-b --timeout=300s

kubectl -n pedidos get pods,svc,ingress
echo
echo "pronto! agora rode ./scripts/k8s-acesso.sh"
