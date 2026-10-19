#!/bin/bash
# libera o acesso ao Ingress em http://localhost:8081
# (port-forward no service do ingress controller, entao a requisicao continua passando pelo ingress)
pkill -f "port-forward.*ingress-nginx" 2>/dev/null
nohup kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8081:80 > /tmp/port-forward.log 2>&1 &
sleep 3
curl -s http://localhost:8081/health && echo
echo "aplicacao no kubernetes: http://localhost:8081"
