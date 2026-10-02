# Arquitetura: devops-05-platform

## Visão geral

```mermaid
flowchart TB
    User(["Usuário"]) -->|HTTPS| CF

    subgraph AWS["AWS us-east-1 · uma conta"]
        CF["CloudFront<br/>*.cloudfront.net"]

        subgraph Shared["Camada shared"]
            ECR[("ECR devops-05-app<br/>imutável")]
            OIDC["Provider OIDC<br/>do GitHub"]
            Roles["Roles do pipeline<br/>build · dev · prod"]
        end

        subgraph Prod["VPC prod 10.60.0.0/16"]
            ALBp["ALB<br/>só CloudFront + cabeçalho"]
            ECSp["ECS Fargate<br/>2 tasks em 2 AZs"]
            RDSp[("RDS PostgreSQL<br/>Multi-AZ")]
            BKP["AWS Backup<br/>diário, 7 dias"]
        end

        subgraph Dev["VPC dev 10.50.0.0/16"]
            ALBd["ALB"]
            ECSd["ECS Fargate<br/>1 task"]
            RDSd[("RDS PostgreSQL<br/>single-AZ")]
            SCH["Scheduler<br/>8h liga · 19h desliga"]
        end

        SM["Secrets Manager<br/>senha gerenciada pelo RDS"]
        BUD["Budgets<br/>um por ambiente"]
    end

    CF -->|HTTP + X-Origin-Verify| ALBp
    CF -.->|outra distribuição| ALBd
    ALBp --> ECSp --> RDSp
    ALBd --> ECSd --> RDSd
    RDSp --> BKP
    SCH --> ECSd
    SCH --> RDSd
    ECSp -.-> SM
    ECSd -.-> SM
    ECR -.->|mesmo digest| ECSd
    ECR -.->|mesmo digest| ECSp
```

Cada ambiente tem a sua distribuição CloudFront; o diagrama mostra uma só
para não repetir o caminho.

## Rede de um ambiente

```mermaid
flowchart TB
    IGW["Internet Gateway"]

    subgraph VPC["VPC 10.x0.0.0/16"]
        subgraph Pub["Pública · x.0.0/24 e x.1.0/24"]
            ALB["ALB"]
            NAT["NAT Gateway<br/>dev: 1 · prod: 1 por AZ"]
        end
        subgraph App["Privada de aplicação · x.10.0/24 e x.11.0/24"]
            Tasks["Tasks Fargate"]
        end
        subgraph Data["Privada de dados · x.20.0/24 e x.21.0/24"]
            DB[("RDS")]
        end
    end

    IGW --- Pub
    ALB -->|porta 8000| Tasks
    Tasks -->|5432 com TLS| DB
    Tasks -->|ECR, Logs, Secrets Manager| NAT --> IGW
```

| Security group | Entrada | Saída |
|---|---|---|
| ALB | 80 a partir da prefix list `com.amazonaws.global.cloudfront.origin-facing` | 8000 para o CIDR da VPC |
| Tasks | 8000 a partir do SG do ALB | Tudo (NAT e banco) |
| Banco | 5432 a partir do SG das tasks | Nenhuma regra |
| Default da VPC | Esvaziado | Esvaziado |

A subnet de dados não tem rota para a internet. A tabela de rotas de
aplicação é uma por AZ: no prod, cada AZ sai pelo próprio NAT e a perda de
uma zona não derruba a saída da outra.

## Caminho de uma requisição

```mermaid
sequenceDiagram
    participant U as Usuário
    participant CF as CloudFront
    participant ALB as ALB
    participant T as Task
    participant DB as RDS

    U->>CF: HTTPS GET /tasks
    CF->>ALB: HTTP + X-Origin-Verify
    alt cabeçalho correto
        ALB->>T: encaminha para o target group
        T->>DB: SELECT (TLS)
        DB-->>T: linhas
        T-->>U: 200 + cabeçalhos de segurança
    else sem o cabeçalho ou outra distribuição
        ALB-->>CF: 403 Acesso direto ao ALB não permitido
    end
```

A prefix list do CloudFront aceita qualquer distribuição de qualquer conta.
O cabeçalho é o que prova que a requisição veio da nossa.

## Pipeline e promoção

```mermaid
sequenceDiagram
    participant Dev as Desenvolvedor
    participant GH as GitHub Actions
    participant AWS as AWS
    participant Rev as Aprovador

    Dev->>GH: push na main (app/)
    GH->>GH: ruff, build, teste com PostgreSQL
    GH->>GH: Trivy (bloqueia HIGH e CRITICAL), SBOM
    GH->>AWS: OIDC sub=ref:refs/heads/main → role de build
    GH->>AWS: push no ECR (tag = SHA)
    GH->>GH: cosign sign (keyless, identidade = app.yml na main)
    GH->>AWS: OIDC sub=environment:dev → role de deploy do dev
    GH->>GH: cosign verify
    GH->>AWS: nova task definition (imagem@digest) e update-service
    AWS-->>GH: serviço estável
    GH->>GH: smoke test pelo CloudFront
    GH->>Rev: aguardando aprovação no Environment prod
    Rev->>GH: aprova
    GH->>AWS: OIDC sub=environment:prod → role de deploy do prod
    GH->>GH: cosign verify do mesmo digest
    GH->>AWS: nova task definition e update-service no prod
    GH->>GH: smoke test pelo CloudFront
```

| Workflow | Quando roda | O que faz |
|---|---|---|
| `seguranca.yml` | Todo push e PR | gitleaks em todo o histórico |
| `infra.yml` | Mudança em `bootstrap/` ou `terraform/` | fmt, validate nas 4 raízes, tflint e checkov |
| `app.yml` | Mudança em `app/` | lint, build, testes, Trivy, SBOM, push, assinatura e promoção |
| `deploy.yml` | Chamado pelo `app.yml` | verifica a assinatura e faz o deploy num ambiente |

### Permissões das roles do pipeline

| Role | Quem assume (`sub`) | Pode |
|---|---|---|
| `devops-05-pipeline-build` | `repo:...:ref:refs/heads/main` | Push e leitura no repositório ECR |
| `devops-05-pipeline-dev` | `repo:...:environment:dev` | Ler imagem; registrar task definition; atualizar só serviços do cluster `devops-05-dev`; `iam:PassRole` só em `devops-05-dev-*` para `ecs-tasks` |
| `devops-05-pipeline-prod` | `repo:...:environment:prod` | O mesmo, limitado a `devops-05-prod` |

A role do dev não atualiza o serviço do prod nem passa as roles do prod para
uma task definition.

## Horário comercial do dev

```mermaid
flowchart LR
    A["08:00<br/>RDS start"] --> B["08:20<br/>ECS desired 1"]
    C["19:00<br/>ECS desired 0"] --> D["19:10<br/>RDS stop"]
```

De segunda a sexta, no fuso America/Sao_Paulo. O EventBridge Scheduler chama
as APIs direto, sem Lambda, com uma role que só alcança aquele serviço e
aquela instância. O banco liga antes e desliga depois da aplicação, para as
tasks nunca subirem sem banco. O Terraform ignora o `desired_count` do
serviço, então um `apply` não religa o ambiente.

## Backup e restauração

```mermaid
flowchart LR
    RDS[("RDS prod")] -->|03:00 todo dia| Plan["Plano diário"]
    Plan --> Vault[("Cofre devops-05-prod-backup<br/>7 dias")]
    Vault -->|testar-restauracao.sh| Tmp[("devops-05-prod-restore-test")]
    Tmp -->|mede RPO e RTO| Del["apagada no fim"]
```

O cofre usa `force_destroy`: o destroy apaga os pontos de recuperação junto.
Sem isso, o cofre com pontos ficaria para trás.
