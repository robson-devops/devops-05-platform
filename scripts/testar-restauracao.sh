#!/usr/bin/env bash
#
# testar-restauracao.sh
#
# Restaura o ponto de recuperação mais recente do banco do prod numa
# instância temporária, mede o RPO (idade do ponto) e o RTO (do pedido de
# restauração até a instância disponível) e apaga a instância no fim.
#
# Uso (da raiz do projeto): ./scripts/testar-restauracao.sh
# Requer: jq e python3. Compatível com o bash 3.2 do macOS.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ENV_DIR="terraform/envs/prod"

cd "$(dirname "$0")/.."

vault=$(terraform -chdir="$ENV_DIR" output -raw backup_vault_name)
role=$(terraform -chdir="$ENV_DIR" output -raw backup_role_arn)
db_id=$(terraform -chdir="$ENV_DIR" output -raw database_identifier)
restore_id="${db_id%-db}-restore-test"
meta=$(mktemp)

db_arn=$(aws rds describe-db-instances --db-instance-identifier "$db_id" \
  --query 'DBInstances[0].DBInstanceArn' --output text --region "$REGION")

cleanup() {
  if aws rds describe-db-instances --db-instance-identifier "$restore_id" \
       --region "$REGION" >/dev/null 2>&1; then
    echo
    echo "Apagando a instância de teste $restore_id..."
    aws rds delete-db-instance \
      --db-instance-identifier "$restore_id" \
      --skip-final-snapshot \
      --delete-automated-backups \
      --region "$REGION" >/dev/null 2>&1 || true
    aws rds wait db-instance-deleted --db-instance-identifier "$restore_id" --region "$REGION"
    echo "Instância de teste apagada."
  fi
  rm -f "$meta"
}
trap cleanup EXIT

# Espera um job do AWS Backup terminar; $1 = backup|restore, $2 = ID.
wait_job() {
  local kind="$1" id="$2" state
  while :; do
    if [ "$kind" = "backup" ]; then
      state=$(aws backup describe-backup-job --backup-job-id "$id" \
        --query State --output text --region "$REGION")
    else
      state=$(aws backup describe-restore-job --restore-job-id "$id" \
        --query Status --output text --region "$REGION")
    fi
    case "$state" in
      COMPLETED) return 0 ;;
      FAILED | ABORTED | EXPIRED)
        echo "Job $id terminou com $state."
        return 1
        ;;
    esac
    echo "  $(date '+%H:%M:%S') $state"
    sleep 30
  done
}

# shellcheck disable=SC2016  # crases são literais do JMESPath
rp=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$vault" \
  --by-resource-arn "$db_arn" \
  --query 'reverse(sort_by(RecoveryPoints[?Status==`COMPLETED`], &CreationDate))[0].RecoveryPointArn' \
  --output text \
  --region "$REGION")

if [ -z "$rp" ] || [ "$rp" = "None" ]; then
  echo "Ainda não há ponto do plano diário. Iniciando um backup sob demanda..."
  job=$(aws backup start-backup-job \
    --backup-vault-name "$vault" \
    --resource-arn "$db_arn" \
    --iam-role-arn "$role" \
    --query BackupJobId --output text --region "$REGION")
  wait_job backup "$job"
  rp=$(aws backup describe-backup-job --backup-job-id "$job" \
    --query RecoveryPointArn --output text --region "$REGION")
fi

created=$(aws backup describe-recovery-point \
  --backup-vault-name "$vault" \
  --recovery-point-arn "$rp" \
  --query CreationDate --output text --region "$REGION")
rpo=$(python3 -c 'import sys; from datetime import datetime, timezone
c = datetime.fromisoformat(sys.argv[1].replace("Z", "+00:00"))
print(int((datetime.now(timezone.utc) - c).total_seconds()))' "$created")

echo "Ponto de recuperação: $rp"
echo "Criado em: $created"

# Metadados do próprio ponto, com outro nome e sem Multi-AZ.
aws backup get-recovery-point-restore-metadata \
  --backup-vault-name "$vault" \
  --recovery-point-arn "$rp" \
  --query RestoreMetadata --output json --region "$REGION" \
  | jq --arg id "$restore_id" '.DBInstanceIdentifier = $id | .MultiAZ = "false"' > "$meta"

started=$(date +%s)
echo "Restaurando em $restore_id a partir das $(date '+%H:%M:%S')..."
job=$(aws backup start-restore-job \
  --recovery-point-arn "$rp" \
  --iam-role-arn "$role" \
  --metadata "file://$meta" \
  --query RestoreJobId --output text --region "$REGION")
wait_job restore "$job"
aws rds wait db-instance-available --db-instance-identifier "$restore_id" --region "$REGION"
rto=$(($(date +%s) - started))

aws rds describe-db-instances --db-instance-identifier "$restore_id" \
  --query 'DBInstances[0].[DBInstanceStatus,Engine,EngineVersion,StorageEncrypted,AvailabilityZone]' \
  --output text --region "$REGION"

echo
echo "RPO medido (idade do ponto restaurado): $((rpo / 3600)) h $((rpo % 3600 / 60)) min"
echo "RTO medido (pedido até a instância disponível): $((rto / 60)) min $((rto % 60)) s"
