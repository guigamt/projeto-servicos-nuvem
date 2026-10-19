# Roteiro da apresentação

Os scripts param entre cada passo (`[enter para continuar]`) pra dar tempo de explicar.

## Etapa 1 - Docker Compose

```bash
docker compose up -d --build
./scripts/etapa1-demo.sh
```

1. **Containers**: mostra que só o nginx tem porta (8080).
2. **Acesso direto ao A**: `curl localhost:5000` não funciona.
3. **Pedido pelo nginx**: volta 202 com o pedido. Explicar que 202 = aceito, quem processa é o B depois.
4. **Logs**: o mesmo `request_id` aparece no nginx, no A (recebido / publicado) e no B (recebido / processado).
5. **A não conhece B**: as variáveis do A só têm o host do rabbitmq.
6. **Para o B**: fila fica com 0 consumidores.
7. **10 pedidos com o B parado**: o A responde normal e a fila mostra 10 mensagens.
   - explicar: fila durável + mensagem persistente, o A só depende do RabbitMQ
8. **Liga o B**: processa os 10 e a fila volta pra 0.
   - explicar: ack manual, se o B morresse no meio a mensagem voltava pra fila
9. **Extra**: 3 serviços B dividindo 12 pedidos (4 pra cada mais ou menos, por causa do prefetch=1).

Depois: `docker compose down`

## Etapa 2 - Kubernetes

```bash
./scripts/k8s-setup.sh
./scripts/k8s-acesso.sh
./scripts/etapa2-demo.sh
```

1. **O que está rodando**: deployments, statefulset do rabbitmq, services ClusterIP e o ingress.
   - explicar por que o B não tem Service e por que o RabbitMQ é StatefulSet
2. **Pedido pelo Ingress**: seguir o `request_id` no ingress, no A e no B.
3. **Self-healing**: apaga um pod do B e mostra o Kubernetes criando outro até voltar pra 2/2.
4. **Persistência**: zera o B, manda 5 pedidos, apaga o pod do rabbitmq. Quando ele volta as 5 mensagens continuam lá. Volta o B e a fila esvazia.
   - falar da limitação de ter só 1 réplica do RabbitMQ

## Etapa 3 - Escalabilidade e elasticidade

```bash
./scripts/etapa3-demo.sh
```

Dica: deixar outro terminal aberto com `kubectl -n pedidos get hpa,pods --watch`

1. **Escala manual pra 4**: `kubectl scale`.
2. **20 pedidos** divididos entre os 4 pods. Isso é **escalabilidade** (manual).
3. Volta pra 2.
4. **Liga o HPA** (mín 1, máx 5, alvo 50% CPU). Sem carga ele desce sozinho pra 1 (o script espera isso).
5. **300 pedidos**: a tabela mostra a cada 10s a CPU, as réplicas e a fila. A CPU sobe, o HPA aumenta os pods, a fila acaba, a CPU cai e os pods vão diminuindo até 1. No final aparecem os eventos do HPA.
   - isso é **elasticidade** (automática). Relacionar com a elasticidade rápida do NIST

Leva uns 6 a 8 minutos.

## Possíveis perguntas

- **Por que não o A chamar o B direto por HTTP?** O A ia precisar saber onde o B está e ia falhar se o B estivesse fora. Com a fila o A só depende do RabbitMQ.
- **E se o B cair no meio de um pedido?** Como o ack é manual, a mensagem sem ack volta pra fila e é processada de novo.
- **E se o RabbitMQ cair?** As mensagens estão no volume. Enquanto ele volta, o A responde 503 e o B fica tentando reconectar.
- **Por que tem requests de CPU no B?** O HPA calcula a % de uso em cima do request.
- **Por que demora pra descer?** Configuramos 1 minuto de espera e 1 pod a cada 30s, pra não ficar subindo e descendo toda hora.
