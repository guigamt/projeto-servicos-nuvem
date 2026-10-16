# Projeto - Serviços de Nuvem

Aplicação distribuída de **pedidos** usando containers, mensageria, orquestração e elasticidade.

Disciplina: Serviços de Nuvem (Engenharia da Computação) - Prof. José Carmino Gomes Jr.

**Integrantes**

- Guilherme Piragibe Ramos Meira
- _(adicionar os demais integrantes)_

## Ideia geral

O domínio escolhido foi um sistema simples de pedidos de uma loja. O cliente faz um pedido, o **Serviço A** (API) recebe, valida e publica uma mensagem no **RabbitMQ**. O **Serviço B** (worker) consome essa mensagem e faz o "processamento" do pedido (simulamos um cálculo pesado que gasta CPU, tipo cálculo de frete e emissão de nota). O **NGINX** é a única porta de entrada.

```
Cliente --HTTP--> NGINX --> Serviço A --publica--> RabbitMQ --entrega--> Serviço B
```

A e B não se conhecem. Nenhum dos dois tem o endereço do outro e não existe chamada HTTP entre eles. Toda a comunicação passa pela fila `pedidos`.

A explicação completa das decisões está em [docs/arquitetura.md](docs/arquitetura.md) e o passo a passo da apresentação está em [docs/roteiro-demonstracao.md](docs/roteiro-demonstracao.md).

## Estrutura do repositório

```
servico-a/            API de pedidos (Python + FastAPI), produtor
servico-b/            worker (Python + pika), consumidor
nginx/nginx.conf      reverse proxy da etapa 1
compose.yml           etapa 1 (Docker Compose)
compose.debug.yml     opcional: painel do RabbitMQ só em 127.0.0.1
k8s/                  etapa 2 (manifestos Kubernetes)
k8s/hpa/              etapa 3 (HorizontalPodAutoscaler)
scripts/              scripts de subida, demonstração e testes
docs/                 documentação
.devcontainer/        ambiente pronto para GitHub Codespaces
.github/workflows/    testes automáticos (GitHub Actions)
```

## Como rodar

O jeito mais fácil é pelo **GitHub Codespaces**, que já vem com Docker, kubectl e minikube instalados (configurado em `.devcontainer/`). Também funciona em qualquer máquina com Docker, minikube e kubectl.

### Credenciais

As senhas não ficam no repositório. O arquivo `.env` é criado a partir do `.env.example` (no Codespaces isso acontece sozinho, com senha aleatória):

```bash
cp .env.example .env   # depois troque a senha
```

### Etapa 1 - Docker Compose

```bash
docker compose up -d --build
docker compose ps
```

A aplicação fica em `http://localhost:8080`. Só o NGINX publica porta.

Demonstração guiada (inclui a falha controlada do Serviço B):

```bash
./scripts/etapa1-demo.sh
```

Para desligar: `docker compose down` (o volume do RabbitMQ continua; `docker compose down -v` apaga tudo).

### Etapa 2 - Kubernetes (minikube)

Antes, desligue o Compose (`docker compose down`) para liberar recursos.

```bash
./scripts/k8s-setup.sh     # sobe o minikube, ingress, metrics-server, imagens e manifestos
./scripts/k8s-acesso.sh    # abre o acesso pelo Ingress em http://localhost:8081
./scripts/etapa2-demo.sh   # self-healing, Service estável e persistência do RabbitMQ
```

### Etapa 3 - Escalabilidade e elasticidade

```bash
./scripts/etapa3-demo.sh   # escala manual e depois HPA com carga artificial
```

Comandos úteis:

```bash
kubectl -n pedidos get pods,hpa
kubectl -n pedidos get hpa servico-b --watch
./scripts/fila.sh k8s              # estado da fila
./scripts/gerar-carga.sh 1500 http://localhost:8081
```

## Endpoints (sempre pelo ponto de entrada)

| Método | Caminho | O que faz |
|---|---|---|
| GET | `/` | página simples para criar pedidos e ver a fila |
| POST | `/api/pedidos` | cria um pedido e publica na fila |
| POST | `/api/pedidos/lote` | cria N pedidos aleatórios (usado para gerar carga) |
| GET | `/api/fila` | quantas mensagens estão esperando e quantos consumidores existem |
| GET | `/api/health/live` e `/api/health/ready` | usados pelos healthchecks e probes |

Exemplo:

```bash
curl -X POST http://localhost:8080/api/pedidos \
  -H 'Content-Type: application/json' \
  -d '{"cliente":"ana","itens":[{"produto":"caneca","quantidade":2}]}'
```

## Testes automáticos

A cada push o GitHub Actions roda `scripts/teste-compose.sh` (fluxo completo, falha do consumidor e restart do broker) e `scripts/teste-k8s.sh` (implantação no minikube, self-healing, escala manual e HPA).

## Referências

- Docker Compose: https://docs.docker.com/compose/
- Kubernetes HPA: https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/
- Kubernetes Self-Healing: https://kubernetes.io/docs/concepts/architecture/self-healing/
- Kubernetes Service: https://kubernetes.io/docs/concepts/services-networking/service/
- NGINX Reverse Proxy: https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/
- RabbitMQ Work Queues: https://www.rabbitmq.com/tutorials
- MELL, P.; GRANCE, T. The NIST Definition of Cloud Computing. NIST SP 800-145, 2011.
