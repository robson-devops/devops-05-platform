# Validação na AWS: Projeto 5

Cada camada é validada antes da seguinte. Os comandos rodam da raiz do
projeto, na us-east-1. Os campos "Resultado" são preenchidos na execução.

## 1. Camada shared

```bash
terraform -chdir=terraform/shared output
```

Esperado: `ecr_repository_url`, `build_role_arn` e o mapa `deploy_role_arn`
com `dev` e `prod`.

Os secrets no GitHub:

```bash
for env in "" dev prod; do
  echo "== ${env:-repositório}"
  GH_PAGER=cat gh secret list \
    --repo robson-devops/devops-05-platform \
    ${env:+--env=$env}
done
```

Esperado: `AWS_BUILD_ROLE_ARN` no repositório e `AWS_DEPLOY_ROLE_ARN` em
`dev` e em `prod`.

**Resultado:** validado em 02/10/2026.

## 2. Primeira imagem

Depois do push, a imagem com a tag do commit e a assinatura do cosign
(`sha256-<digest>.sig`):

```bash
aws ecr describe-images \
  --repository-name devops-05-app \
  --query 'imageDetails[].[imageTags[0],imagePushedAt]' \
  --output text
```

A verificação feita pelo pipeline, repetida localmente (requer cosign):

```bash
DIGEST=$(aws ecr describe-images \
  --repository-name devops-05-app \
  --image-ids imageTag="$IMAGE_TAG" \
  --query 'imageDetails[0].imageDigest' --output text)
REPO=$(terraform -chdir=terraform/shared output -raw ecr_repository_url)

aws ecr get-login-password | docker login --username AWS --password-stdin "${REPO%%/*}"
cosign verify \
  --certificate-identity "https://github.com/robson-devops/devops-05-platform/.github/workflows/app.yml@refs/heads/main" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "$REPO@$DIGEST"
```

**Resultado:** a preencher.

## 3. Rede e banco do dev

Rotas por camada (a de dados sem rota padrão):

```bash
aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values="$(terraform -chdir=terraform/envs/dev output -raw vpc_id)" \
  --query 'RouteTables[].[Tags[?Key==`Name`].Value|[0],Routes[?DestinationCidrBlock==`0.0.0.0/0`]|[0].[NatGatewayId,GatewayId]]' \
  --output text
```

Esperado: `devops-05-dev-public` com `igw-...`, as duas `devops-05-dev-app-*`
com o mesmo `nat-...` e `devops-05-dev-data` sem rota padrão.

Banco disponível, privado e cifrado:

```bash
aws rds describe-db-instances \
  --db-instance-identifier devops-05-dev-db \
  --query 'DBInstances[0].[DBInstanceStatus,MultiAZ,PubliclyAccessible,StorageEncrypted,MasterUserSecret.SecretStatus]' \
  --output text
```

Esperado: `available  False  False  True  active`

**Resultado:** a preencher.

## 4. Aplicação no dev

```bash
APP_URL=$(terraform -chdir=terraform/envs/dev output -raw app_url)
curl -s "$APP_URL/health"
curl -s "$APP_URL/ready"
curl -sI "http://${APP_URL#https://}/health" | head -n1
```

Esperado: versão igual ao `IMAGE_TAG` e `"environment":"dev"`; `/ready` com
`ready`, o que prova a conexão TLS com o banco; HTTP redirecionado para
HTTPS (`301`).

O ALB recusa quem não é o CloudFront. De um IP comum, o security group nem
responde e o `curl` desiste por tempo:

```bash
curl -s -m 5 -o /dev/null -w '%{http_code}\n' \
  "http://$(terraform -chdir=terraform/envs/dev output -raw alb_dns_name)/health"
```

Esperado: `000`. A segunda barreira, para quem vem da rede do CloudFront sem
o cabeçalho, está nas regras do listener:

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers --names devops-05-dev-alb \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)
LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[0].ListenerArn' --output text)
aws elbv2 describe-rules --listener-arn "$LISTENER_ARN" \
  --query 'Rules[].[Priority,Conditions[0].HttpHeaderConfig.HttpHeaderName,Actions[0].Type,Actions[0].FixedResponseConfig.StatusCode]' \
  --output text
```

Esperado: prioridade `1` com `X-Origin-Verify` e `forward`; `default` com
`fixed-response` e `403`.

CRUD pela borda:

```bash
curl -s -X POST "$APP_URL/tasks" \
  -H 'Content-Type: application/json' \
  -d '{"title":"validação"}'
curl -s "$APP_URL/tasks"
```

**Resultado:** a preencher.

## 5. Prod com Multi-AZ

```bash
aws rds describe-db-instances \
  --db-instance-identifier devops-05-prod-db \
  --query 'DBInstances[0].[MultiAZ,AvailabilityZone,SecondaryAvailabilityZone]' \
  --output text

aws ecs list-tasks --cluster devops-05-prod --service-name devops-05-prod \
  --query 'taskArns' --output text \
  | xargs aws ecs describe-tasks --cluster devops-05-prod \
      --query 'tasks[].[availabilityZone,lastStatus]' --output text --tasks
```

Esperado: `True` com AZs diferentes para a primária e a standby; duas tasks
`RUNNING`, uma em cada AZ.

### Failover forçado

```bash
./scripts/testar-failover.sh
```

O script faz uma requisição por segundo em `/ready` pelo CloudFront, força o
failover com `reboot-db-instance --force-failover` e mostra os eventos do RDS e a
maior janela em que a aplicação ficou sem banco.

Resultado em 02/10/2026, com a primária em `us-east-1a`:

| Medida | Resultado |
|---|---|
| Failover segundo o RDS (`started` → `completed`) | 19:18:10 → 19:18:55, **45 s** |
| Requisições com erro em `/ready` | 14 de 91 (`503` do banco indisponível e `000` por timeout de 2 s) |
| Maior janela sem banco vista pela aplicação | **27 s** |

A aplicação voltou antes do evento `completed`: o `pool_pre_ping` do
SQLAlchemy descarta as conexões mortas e reconecta no novo primário assim que
o DNS do endpoint muda. O atributo `AvailabilityZone` da API continuou
mostrando a AZ antiga por alguns minutos depois do failover; por isso o
script usa os eventos do RDS como fonte.

## 6. Pipeline e promoção

Mude algo em `app/`, faça commit e push, e acompanhe:

```bash
gh run watch --repo robson-devops/devops-05-platform
```

| Momento | Resultado |
|---|---|
| Push até a imagem assinada | a preencher |
| Push até a versão nova no dev (smoke test) | a preencher |
| Aprovação até a versão nova no prod | a preencher |
| Mesmo digest no dev e no prod | a preencher |

Conferir o digest nos dois ambientes:

```bash
for env in dev prod; do
  aws ecs describe-task-definition --task-definition "devops-05-$env" \
    --query 'taskDefinition.containerDefinitions[0].image' --output text
done
```

### Imagem sem assinatura é recusada

Uma imagem enviada ao ECR por fora do pipeline não tem assinatura. Rodar o
workflow de deploy com ela falha no passo "Conferir a assinatura da imagem".
O teste: publicar uma tag manual e chamar o `cosign verify` do passo 2 com o
digest dela.

**Resultado:** a preencher.

### Isolamento das roles

A role do dev não alcança o prod. Assumindo a role do dev pela CLI não é
possível (ela só confia no OIDC do GitHub), então a prova é a própria policy:

```bash
aws iam get-role-policy \
  --role-name devops-05-pipeline-dev \
  --policy-name devops-05-pipeline-dev-permissions \
  --query 'PolicyDocument.Statement[?Sid==`UpdateOwnService` || Sid==`PassOwnTaskRoles`].Resource'
```

Esperado: só ARNs com `devops-05-dev`.

## 7. Backup e restauração

```bash
./scripts/testar-restauracao.sh
```

O script grava uma tarefa marcadora no prod pelo CloudFront, faz um backup
sob demanda, restaura esse ponto numa instância temporária e roda uma task
avulsa do ECS, na rede do prod, apontando o `DB_HOST` para o banco
restaurado. A task procura o marcador e termina com código 0 só se o
encontrar. A instância temporária é apagada no fim, mesmo se o script falhar.

| Medida | Resultado |
|---|---|
| RPO | até 24 h, pela frequência do plano diário |
| RTO (pedido até a instância disponível) | a preencher |
| Marcador encontrado no banco restaurado | a preencher |
| Instância temporária apagada no fim | a preencher |

Na primeira execução, a restauração falhou porque o script repassava todos os
metadados do ponto de recuperação, e a AWS recusa o `DBSnapshotIdentifier`
nessa chamada. O script passou a enviar só o necessário para a instância
cair na rede do prod.

## 8. FinOps

Agendamentos do dev:

```bash
aws scheduler list-schedules \
  --name-prefix devops-05-dev \
  --query 'Schedules[].[Name,State]' --output text
```

Esperado: `banco-liga`, `app-liga`, `app-desliga` e `banco-desliga` em
`ENABLED`. Para testar sem esperar o horário, dispare o mesmo efeito pela
CLI:

```bash
aws ecs update-service --cluster devops-05-dev --service devops-05-dev --desired-count 0
aws rds stop-db-instance --db-instance-identifier devops-05-dev-db
```

Orçamentos:

```bash
aws budgets describe-budgets \
  --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --query 'Budgets[].[BudgetName,BudgetLimit.Amount,CostFilters]'
```

**Resultado:** a preencher.

## 9. Encerramento

| Passo | Resultado |
|---|---|
| `./scripts/encerrar.sh` | a preencher |
| `./scripts/verificar-cobranca.sh us-east-1` | a preencher |
