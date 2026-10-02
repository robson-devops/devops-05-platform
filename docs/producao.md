# Do laboratório à produção

O projeto foi feito para ser reproduzido por qualquer pessoa, numa conta de
estudo, e apagado no mesmo dia. Algumas decisões de produção não cabem nesse
formato, por exigirem domínio, várias contas ou custo fixo. Este documento
diz o que mudaria, por quê, quanto custa e como implementar cada uma.

Custos aproximados da us-east-1, em dólares.

## 1. Uma conta por ambiente

**O que muda.** AWS Organizations com contas separadas: `shared-services`
(ECR e pipeline), `dev`, `prod`, `log-archive` e `security`. O Control Tower
monta a landing zone com CloudTrail e Config centralizados.

**Por quê.** Na mesma conta, o isolamento depende de cada policy estar certa.
Com contas separadas, um erro de permissão no dev não alcança o prod: a
fronteira é a conta. Cotas, faturamento e Service Control Policies também
passam a ser por ambiente.

**Custo.** Organizations e contas não cobram. Control Tower cobra pelos
serviços que liga (Config e CloudTrail), da ordem de alguns dólares por conta
por mês.

**Como implementar.**

- `terraform/shared` vai para a conta `shared-services`. O repositório ECR
  ganha uma policy que libera `ecr:BatchGetImage` e
  `ecr:GetDownloadUrlForLayer` para as contas dev e prod.
- Cada `terraform/envs/<env>` passa a ter o seu bucket de state, na conta do
  ambiente. O provider assume uma role da conta de destino (`assume_role`).
- As roles de deploy são criadas em cada conta, com a mesma trust policy por
  GitHub Environment.
- SCPs negam o que nenhum ambiente deve fazer, como sair da organização,
  desligar o CloudTrail ou usar regiões fora da lista.

## 2. Domínio próprio e HTTPS até a origem

**O que muda.** Hosted zone no Route 53, certificado ACM para o CloudFront
(precisa ser na us-east-1) e outro para o ALB, listener 443 no ALB e
`origin_protocol_policy = "https-only"` no CloudFront.

**Por quê.** Hoje o trecho CloudFront → ALB é HTTP. Com certificado no ALB, o
tráfego é cifrado de ponta a ponta. O domínio também tira a dependência do
`*.cloudfront.net` e permite fixar `TLSv1.2_2021` como versão mínima para o
usuário.

**Custo.** Domínio de US$ 13 a 15 por ano, hosted zone a US$ 0,50 por mês.
Certificados ACM públicos são gratuitos.

**Como implementar.**

- Uma variável `domain_name` no módulo `platform`.
- `aws_route53_zone` e `aws_acm_certificate` com validação por DNS
  (`aws_route53_record` e `aws_acm_certificate_validation`).
- `aliases` e `viewer_certificate { acm_certificate_arn, minimum_protocol_version = "TLSv1.2_2021", ssl_support_method = "sni-only" }`
  na distribuição.
- Listener HTTPS no ALB com `ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"`
  e o listener 80 só redirecionando.
- Registros `A`/`AAAA` do tipo alias apontando para o CloudFront.

Outra opção é o CloudFront VPC Origin, com o ALB interno, sem IP público.
Ele dispensa a prefix list e o cabeçalho, mas cria um security group
gerenciado pela AWS que pode atrasar a exclusão da VPC.

## 3. WAF

**O que muda.** Uma Web ACL associada ao CloudFront com os grupos gerenciados
`AWSManagedRulesCommonRuleSet`, `AWSManagedRulesKnownBadInputsRuleSet` e
`AWSManagedRulesAmazonIpReputationList`, mais uma regra de limite de taxa
por IP.

**Por quê.** Barra injeção, payloads conhecidos e abuso de volume antes de
chegar à aplicação, e dá visibilidade do que foi bloqueado.

**Custo.** US$ 5 por Web ACL, US$ 1 por regra ou grupo, US$ 0,60 por milhão
de requisições. Com quatro regras, cerca de US$ 9 por mês mais o tráfego.

**Como implementar.** `aws_wafv2_web_acl` com `scope = "CLOUDFRONT"` (criada na
us-east-1) e `web_acl_id` na distribuição. Começar com as regras em modo
`count`, olhar os logs por uma semana e só então passar para `block`.

## 4. Terraform aplicado pelo pipeline

**O que muda.** Pull request roda `terraform plan` e publica o resultado no
PR. Merge na `main` roda `apply` no dev; o `apply` no prod espera aprovação no
Environment, como o deploy da aplicação.

**Por quê.** Toda mudança de infraestrutura passa a ter revisão, histórico e
o mesmo caminho do código. Ninguém aplica do próprio notebook.

**Custo.** Nenhum além dos minutos do GitHub Actions.

**Como implementar.**

- Uma role de infraestrutura por ambiente, assumível só pelo Environment
  correspondente, com permission boundary: ela pode criar roles, mas só com
  o mesmo boundary e com o prefixo do projeto.
- O plan salvo como artefato e o apply usando exatamente esse plan.
- Um `terraform plan -detailed-exitcode` agendado todo dia para detectar
  drift, abrindo uma issue quando houver diferença.

## 5. Proteção dos dados

**O que muda.**

| Recurso | Laboratório | Produção |
|---|---|---|
| RDS | `deletion_protection = false`, sem snapshot final | `true`, com snapshot final |
| ECR | `force_delete = true` | `false` |
| Cofre do Backup | `force_destroy = true` | `false`, com Vault Lock em modo compliance |
| Criptografia | Chaves gerenciadas pela AWS | Chave KMS própria por ambiente |
| ALB | Sem proteção contra exclusão | `enable_deletion_protection = true` |

**Por quê.** No laboratório, o destroy precisa apagar tudo. Em produção, é
justamente o que se quer impedir. O Vault Lock impede que alguém, mesmo com
permissão de administrador, apague os backups antes do prazo, o que protege
contra ransomware.

**Custo.** US$ 1 por chave KMS por mês, mais as chamadas. O snapshot final
custa o armazenamento dele.

**Como implementar.** Os valores já são variáveis nos módulos; o prod passa
a usar os de produção. `aws_backup_vault_lock_configuration` com
`min_retention_days` e `changeable_for_days`.

## 6. Recuperação de desastre entre regiões

**O que muda.** O plano do AWS Backup ganha uma `copy_action` para um cofre
em outra região (por exemplo us-west-2). Para RTO menor, uma réplica de
leitura do RDS na outra região, promovida em caso de desastre.

**Por quê.** O Multi-AZ protege contra a perda de uma zona, não de uma
região inteira. A cópia entre regiões protege os dados; a réplica reduz o
tempo de volta.

**Custo.** Transferência entre regiões (US$ 0,02 por GB) e o armazenamento
da cópia. A réplica custa uma instância a mais, de forma contínua.

**Como implementar.** O módulo `platform` aplicado também na segunda região,
com o serviço ECS em zero tasks (pilot light). O runbook de failover: promover
a réplica, subir as tasks e trocar a origem do CloudFront ou o registro DNS.

## 7. Teste de restauração agendado

**O que muda.** O `scripts/testar-restauracao.sh` vira um restore testing
plan do AWS Backup, que restaura o ponto mais recente toda semana, valida e
apaga a instância sozinho.

**Por quê.** O teste deixa de depender de alguém lembrar de rodar o script,
e o resultado de cada execução fica registrado.

**Custo.** A instância restaurada durante a janela de validação, algumas
horas por semana.

**Como implementar.** `aws_backup_restore_testing_plan` e
`aws_backup_restore_testing_selection`, com o subnet group e o security
group nos metadados da restauração. Uma regra do EventBridge no evento de
fim do job alimenta a métrica de RTO e avisa quando falha.

## 8. Observabilidade e SLO

**O que muda.** Alarmes no CloudWatch para 5xx do ALB, latência p99,
targets sem saúde, CPU e espaço livre do RDS e falha de job do Backup, todos
num tópico SNS ligado ao plantão. SLO de disponibilidade medido pelas
métricas do ALB, com alerta por consumo do orçamento de erro.

**Por quê.** Hoje quem descobre o problema é o usuário. O projeto 3 mostra a
mesma ideia com Prometheus e Alertmanager.

**Custo.** US$ 0,10 por alarme por mês; Container Insights e logs pelo
volume ingerido.

**Como implementar.** Um módulo `alarm` chamado pelo `platform`, com os
limites como variáveis por ambiente; no dev, alarmes só por e-mail.

## 9. Rede e custo de saída

**O que muda.** VPC endpoints de gateway para o S3 (grátis) e de interface
para ECR, CloudWatch Logs e Secrets Manager.

**Por quê.** O tráfego das tasks para essas APIs deixa de passar pelo NAT,
que cobra US$ 0,045 por GB processado. Com muitas tasks ou deploys
frequentes, o endpoint se paga.

**Custo.** O endpoint de gateway do S3 é gratuito. Cada endpoint de interface
custa US$ 0,01 por hora por AZ, cerca de US$ 7 por mês por AZ.

**Como implementar.** `aws_vpc_endpoint` no módulo `network`, com um
security group que aceita 443 só das subnets de aplicação.

## 10. Compute mais barato

**O que muda.** Tasks em Graviton (`cpu_architecture = "ARM64"`), Fargate
Spot no dev e Compute Savings Plans para a base do prod.

**Por quê.** Graviton custa cerca de 20% menos pela mesma capacidade. Spot
chega a 70% de desconto, aceitável onde uma interrupção não importa. O
Savings Plan reduz o custo fixo do que roda o tempo todo.

**Custo.** Nenhum adicional; o Savings Plan é um compromisso de 1 ou 3 anos.

**Como implementar.** Build multi-arquitetura com `docker buildx`;
`capacity_provider_strategy` com `FARGATE_SPOT` no dev.

## 11. Cadeia de suprimentos

**O que muda.** Branch protection na `main` com os workflows como checagem
obrigatória e revisão de PR; Environment `prod` aceitando deploy só da
`main`; attestation de proveniência (SLSA) e do SBOM com `cosign attest`;
actions fixadas por SHA do commit em vez de tag.

**Por quê.** A assinatura prova quem gerou a imagem. A proveniência prova
como ela foi gerada, e o SHA impede que uma tag de action seja trocada por
código malicioso.

**Custo.** Nenhum.

**Como implementar.** Regras de branch e de Environment pela API do GitHub
(ou pelo provider `integrations/github` no Terraform); Dependabot para manter
os SHAs das actions atualizados.

## 12. Banco

**O que muda.** RDS Proxy entre as tasks e o banco; migrações com Alembic
rodando numa task separada antes do deploy.

**Por quê.** O proxy mantém as conexões durante o failover e reduz a janela
sem banco vista pela aplicação. Migração no startup da aplicação, com várias
tasks subindo juntas, vira condição de corrida quando o schema evolui.

**Custo.** RDS Proxy cobra por vCPU da instância, cerca de US$ 0,015 por vCPU
por hora (mínimo de 2 vCPUs).

**Como implementar.** `aws_db_proxy` com o secret gerenciado pelo RDS; o
`DB_HOST` da task passa a ser o endpoint do proxy. A migração vira um
`aws ecs run-task` no pipeline, antes do update do serviço.
