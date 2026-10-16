#!/usr/bin/env bash
# Abre o acesso a aplicacao PELO INGRESS CONTROLLER em http://localhost:8081
# (o trafego continua passando pelo NGINX Ingress; nada aponta direto pros pods)
set -euo pipefail
pkill -f "port-forward.*ingress-nginx-controller" 2>/dev/null || true
nohup kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8081:80 --address 0.0.0.0 \
  > /tmp/port-forward-ingress.log 2>&1 &
sleep 3
curl -sS -m 5 http://localhost:8081/api/health/ready && echo
echo ">> aplicacao no Kubernetes: http://localhost:8081"
