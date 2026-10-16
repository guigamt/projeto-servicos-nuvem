# Roteiro da demonstração

Ordem sugerida para apresentar. Cada script para entre os passos (`[Enter para continuar]`) para dar tempo de explicar. Embaixo de cada passo tem o que falar.

Ambiente: GitHub Codespaces (ou máquina com Docker + minikube). Terminal na pasta do projeto.

---

## Etapa 1 - Docker Compose

```bash
docker compose up -d --build
./scripts/etapa1-demo.sh
```

1. **Containers e portas.** Mostra os 4 containers e que só o NGINX tem porta publicada (`0.0.0.0:8080->80`).
   _Falar:_ o NGINX é o reverse proxy e o único ponto de entrada. A e B estão na rede `backend`, que é `internal`.
2. **Acesso direto ao Serviço A falha.** `curl localhost:8000` não conecta.
3. **Pedido pelo NGINX.** Volta `202` com `pedido_id` e `request_id`.
   _Falar:_ 202 porque o pedido foi aceito e enfileirado, quem processa é o B, de forma assíncrona.
4. **Rastreio pelos logs.** O mesmo `request_id` aparece no NGINX, no A (recebido e publicado) e no B (recebido e processado).
5. **A não conhece B.** As variáveis do Serviço A só têm o host do RabbitMQ e o nome da fila.
6. **Falha controlada: para o Serviço B.** A fila fica com 0 consumidores.
7. **Cria 10 pedidos com o B parado.** Todos voltam HTTP 202 e a fila mostra `messages_ready = 10`.
   _Falar:_ o produtor não depende do consumidor estar vivo. As mensagens ficam guardadas porque a fila é durável e as mensagens são persistentes.
8. **Religa o Serviço B.** Ele processa as 10 pendentes e a fila volta para 0.
   _Falar:_ o B só manda `ack` depois de processar; se tivesse caído no meio, a mensagem voltaria para a fila (log mostra `reentrega=True`).
9. **Extra: 3 consumidores.** `--scale servico-b=3`, manda 30 pedidos, mostra quantos cada instância processou (fica perto de 10 cada, por causa do `prefetch=1`).

Desligar antes da etapa 2: `docker compose down`

---

## Etapa 2 - Kubernetes

```bash
./scripts/k8s-setup.sh
./scripts/k8s-acesso.sh
./scripts/etapa2-demo.sh
```

1. **O que está rodando.** Deployments `servico-a` e `servico-b`, StatefulSet `rabbitmq`, Services todos `ClusterIP` e o Ingress.
   _Falar:_ o Serviço B não tem Service porque ninguém conecta nele. RabbitMQ é StatefulSet porque tem estado (nome fixo + volume).
2. **Pedido pelo Ingress + rastreio.** O `request_id` aparece no log do ingress controller, de um pod do A e de um pod do B.
3. **Self-healing (obrigatório).** Apaga um pod do Serviço B e acompanha: aparece um pod novo e o Deployment volta para 2/2.
   _Falar:_ o Kubernetes trabalha com estado desejado (2 réplicas). O controlador vê que tem 1 e cria outro. A aplicação não depende de um pod específico.
4. **Service estável.** Apaga um pod do A enquanto faz requisições: continuam voltando 200 porque o Service manda para o pod que sobrou.
5. **Persistência do RabbitMQ.** Zera o B, gera 5 pedidos, apaga o pod `rabbitmq-0`. Quando ele volta, as 5 mensagens continuam lá (PVC). Volta o B para 2 e a fila esvazia.
   _Falar:_ limitação: com 1 réplica, enquanto o broker reinicia o Serviço A responde 503.

---

## Etapa 3 - Escalabilidade e elasticidade

```bash
./scripts/etapa3-demo.sh
```

Dica: deixar um segundo terminal aberto com `kubectl -n pedidos get hpa,pods --watch`.

1. **Escala manual para 4 réplicas.** A fila mostra 4 consumidores.
2. **4 consumidores dividindo 80 pedidos.** Contagem por pod fica parecida.
   _Falar:_ isso é **escalabilidade**: a gente decidiu o número de réplicas.
3. **Volta para 2.**
4. **Aplica o HPA** (mínimo 1, máximo 6, alvo 50% de CPU). Sem carga ele desce para 1.
5. **Carga artificial (1500 pedidos).** A tabela mostra a cada 10s: CPU, réplicas e mensagens na fila. A CPU dispara, as réplicas sobem até 6, a fila começa a cair mais rápido, depois que zera a CPU cai e as réplicas descem de 1 em 1 até voltar para 1. No final aparecem os eventos do HPA (`New size: ...; reason: cpu resource utilization above target`).
   _Falar:_ isso é **elasticidade**: o próprio ambiente aumentou e liberou recursos conforme a demanda. Relacionar com a "elasticidade rápida" do NIST. Falar que o ideal seria escalar pelo tamanho da fila (KEDA), mas CPU era o requisito mínimo.

Tempo aproximado da etapa 3: 8 a 12 minutos (a descida é de propósito mais lenta).

---

## Perguntas que podem cair

- **Por que não chamar o B direto por HTTP?** Acoplamento: o A teria que saber onde o B está, esperar ele responder e falharia se o B estivesse fora. Com a fila, o A só depende do broker.
- **O que acontece se o B cair no meio de um pedido?** Como o ack é manual, a mensagem não confirmada volta para a fila e outro worker processa.
- **E se o RabbitMQ cair?** Mensagens persistentes ficam no volume. Enquanto ele está fora, o A responde 503 e o B fica tentando reconectar. É o ponto único de falha da solução.
- **Por que o HPA usa o request e não o limit?** A conta de utilização do HPA é `uso / request`. Por isso definimos `requests.cpu` no Deployment do B.
- **Por que a descida é lenta?** Janela de estabilização de 60s e no máximo 1 pod a cada 30s, para não ficar oscilando.
