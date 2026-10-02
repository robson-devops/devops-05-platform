#!/usr/bin/env bash
#
# encerrar.sh
#
# Apaga tudo o que o projeto criou, na ordem inversa da criação:
# prod, dev, shared e bootstrap. Também apaga o que fica fora do state:
# a instância de um teste de restauração interrompido e as revisões de
# task definition registradas pelo pipeline.
#
# Uso (da raiz do projeto): ./scripts/encerrar.sh
# Compatível com o bash 3.2 do macOS.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
PROJECT="devops-05"

# O destroy não usa estes valores, mas as variáveis são obrigatórias.
DESTROY_VARS="-var image_tag=0000000000000000000000000000000000000000 -var alert_email=encerrar@example.com"

cd "$(dirname "$0")/.."

account=$(aws sts get-caller-identity --query Account --output text)
echo "Conta AWS: $account · região: $REGION"
echo "Serão apagados os ambientes prod e dev, a camada shared e o bootstrap."
printf 'Digite encerrar para continuar: '
read -r resposta
if [ "$resposta" != "encerrar" ]; then
  echo "Cancelado."
  exit 1
fi

if ! bucket=$(terraform -chdir=bootstrap output -raw state_bucket_name 2>/dev/null); then
  echo "O bootstrap não tem state local; nada para apagar nas camadas."
  exit 0
fi

destroy_layer() {
  local dir="$1"
  shift
  echo
  echo "== terraform destroy em $dir"
  terraform -chdir="$dir" init -input=false -reconfigure \
    -backend-config="bucket=$bucket" >/dev/null
  # shellcheck disable=SC2086  # DESTROY_VARS precisa ser dividido em palavras
  terraform -chdir="$dir" destroy -auto-approve -input=false "$@"
}

# Usa o subnet group e o security group do prod; precisa sair antes dele.
restore_id="${PROJECT}-prod-restore-test"
if aws rds describe-db-instances --db-instance-identifier "$restore_id" \
     --region "$REGION" >/dev/null 2>&1; then
  echo
  echo "== Apagando a instância de teste $restore_id"
  aws rds delete-db-instance \
    --db-instance-identifier "$restore_id" \
    --skip-final-snapshot \
    --delete-automated-backups \
    --region "$REGION" >/dev/null
  aws rds wait db-instance-deleted --db-instance-identifier "$restore_id" --region "$REGION"
fi

# O force_destroy do cofre não espera a exclusão dos snapshots do RDS; o
# cofre só sai depois que eles somem de fato.
vault="${PROJECT}-prod-backup"
if aws backup describe-backup-vault --backup-vault-name "$vault" \
     --region "$REGION" >/dev/null 2>&1; then
  echo
  echo "== Esvaziando o cofre $vault"
  for rp in $(aws backup list-recovery-points-by-backup-vault \
                --backup-vault-name "$vault" \
                --query 'RecoveryPoints[].RecoveryPointArn' \
                --output text --region "$REGION"); do
    aws backup delete-recovery-point \
      --backup-vault-name "$vault" \
      --recovery-point-arn "$rp" \
      --region "$REGION" 2>/dev/null || true
  done
  while [ "$(aws backup list-recovery-points-by-backup-vault \
               --backup-vault-name "$vault" \
               --query 'length(RecoveryPoints)' \
               --output text --region "$REGION")" != "0" ]; do
    echo "  aguardando a exclusão dos pontos de recuperação..."
    sleep 15
  done
fi

# shellcheck disable=SC2086
destroy_layer terraform/envs/prod $DESTROY_VARS
# shellcheck disable=SC2086
destroy_layer terraform/envs/dev $DESTROY_VARS

echo
echo "== Revisões de task definition registradas pelo pipeline"
for family in "${PROJECT}-dev" "${PROJECT}-prod"; do
  for arn in $(aws ecs list-task-definitions --family-prefix "$family" --status ACTIVE \
                 --query 'taskDefinitionArns[]' --output text --region "$REGION"); do
    aws ecs deregister-task-definition --task-definition "$arn" --region "$REGION" >/dev/null
  done
  for arn in $(aws ecs list-task-definitions --family-prefix "$family" --status INACTIVE \
                 --query 'taskDefinitionArns[]' --output text --region "$REGION"); do
    aws ecs delete-task-definitions --task-definitions "$arn" --region "$REGION" >/dev/null
    echo "  apagada $arn"
  done
done

# O ECS ainda grava métricas logo depois do destroy e recria este log group sem retenção.
for env in dev prod; do
  aws logs delete-log-group \
    --log-group-name "/aws/ecs/containerinsights/${PROJECT}-${env}/performance" \
    --region "$REGION" 2>/dev/null || true
done

destroy_layer terraform/shared

echo
echo "== terraform destroy em bootstrap"
terraform -chdir=bootstrap destroy -auto-approve -input=false

echo
echo "Encerramento concluído em $((SECONDS / 60)) min $((SECONDS % 60)) s."
echo "Confira com: ./scripts/verificar-cobranca.sh $REGION"
echo "Os GitHub Environments e secrets continuam no repositório; não geram custo."
