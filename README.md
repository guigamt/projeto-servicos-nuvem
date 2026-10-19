# Projeto - Serviços de Nuvem

Projeto da disciplina de Serviços de Nuvem (Engenharia da Computação - Mackenzie), prof. José Carmino Gomes Jr.

Integrantes:
- Guilherme Piragibe Ramos Meira
- (colocar os outros integrantes)

## Sobre o projeto

A gente fez um sistema bem simples de pedidos de uma loja. O cliente faz um pedido, o **Serviço A** recebe e manda pra uma fila no **RabbitMQ**, e o **Serviço B** pega da fila e processa. O **NGINX** é a única entrada da aplicação.

```
Cliente -> NGINX -> Serviço A -> RabbitMQ -> Serviço B
```

O A e o B não se conhecem e não se chamam diretamente. Tudo passa pela fila `pedidos`.

- Serviço A: Python + Flask
- Serviço B: Python + pika
- RabbitMQ 4.1
- NGINX

A explicação da arquitetura está em [docs/arquitetura.md](docs/arquitetura.md) e o roteiro da apresentação em [docs/roteiro-demonstracao.md](docs/roteiro-demonstracao.md).

## Pastas

```
servico-a/      API que recebe os pedidos (produtor)
servico-b/      worker que processa os pedidos (consumidor)
nginx/          configuracao do nginx (etapa 1)
compose.yml     docker compose (etapa 1)
k8s/            manifestos do kubernetes (etapa 2)
k8s/hpa/        HPA do servico B (etapa 3)
scripts/        scripts pra subir e demonstrar cada etapa
docs/           documentacao
```

## Senha do RabbitMQ

A senha não fica no código. Ela fica num arquivo `.env` que não vai pro Git:

```bash
cp .env.example .env
# depois troca a senha dentro do .env
```

(ou roda `./scripts/preparar-ambiente.sh`, que já cria o `.env` com uma senha aleatória)

## Etapa 1 - Docker Compose

```bash
docker compose up -d --build
```

Acessar em http://localhost:8080 (página simples pra fazer pedido).

Fazer um pedido pelo terminal:

```bash
curl -X POST http://localhost:8080/pedidos \
  -H "Content-Type: application/json" \
  -d '{"cliente":"maria","produto":"caneca","quantidade":2}'
```

Demonstração (inclui parar o serviço B e mandar 10 pedidos):

```bash
./scripts/etapa1-demo.sh
```

Desligar: `docker compose down`

## Etapa 2 - Kubernetes (minikube)

```bash
docker compose down          # desliga a etapa 1 antes
./scripts/k8s-setup.sh       # sobe minikube, ingress, metrics-server e aplica os yaml
./scripts/k8s-acesso.sh      # libera o acesso pelo ingress em http://localhost:8081
./scripts/etapa2-demo.sh     # self-healing e persistencia do rabbitmq
```

## Etapa 3 - Escalabilidade e HPA

```bash
./scripts/etapa3-demo.sh
```

Comandos úteis:

```bash
kubectl -n pedidos get pods
kubectl -n pedidos get hpa --watch
./scripts/fila.sh k8s
./scripts/gerar-carga.sh 300 http://localhost:8081
```

## Rodando no GitHub

Toda vez que tem push na `main`, o GitHub Actions roda a demonstração inteira (as 3 etapas) e salva o que apareceu no terminal no branch **evidencias** (`etapa1.txt`, `etapa2.txt`, `etapa3.txt`). Também dá pra rodar na mão em Actions -> demonstracao -> Run workflow.

## Referências

- Docker Compose: https://docs.docker.com/compose/
- Kubernetes HPA: https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/
- Kubernetes Self-Healing: https://kubernetes.io/docs/concepts/architecture/self-healing/
- Kubernetes Service: https://kubernetes.io/docs/concepts/services-networking/service/
- NGINX Reverse Proxy: https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/
- RabbitMQ Work Queues: https://www.rabbitmq.com/tutorials
- MELL, P.; GRANCE, T. The NIST Definition of Cloud Computing. NIST SP 800-145, 2011.
