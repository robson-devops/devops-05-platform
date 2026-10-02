#!/usr/bin/env bash
#
# testar-restauracao.sh
#
# Prova que o backup do banco do prod volta com os dados:
#   1. grava uma tarefa marcadora no prod, pelo CloudFront;
#   2. faz um backup sob demanda no cofre do AWS Backup;
#   3. restaura esse ponto numa instância temporária e mede o RTO;
#   4. roda uma task avulsa do ECS, na rede do prod, que procura o marcador
#      no banco restaurado;
#   5. apaga a instância temporária.
#
# Uso (da raiz do projeto): ./scripts/testar-restauracao.sh
# Requer: jq. Compatível com o bash 3.2 do macOS.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ENV_DIR="terraform/envs/prod"

cd "$(dirname "$0")/.."

vault=$(terraform -chdir="$ENV_DIR" output -raw backup_vault_name)
role=$(terraform -chdir="$ENV_DIR" output -raw backup_role_arn)
db_id=$(terraform -chdir="$ENV_DIR" output -raw database_identifier)
app_url=$(terraform -chdir="$ENV_DIR" output -raw app_url)
cluster=$(terraform -chdir="$ENV_DIR" output -raw cluster_name)
service=$(terraform -chdir="$ENV_DIR" output -raw service_name)
restore_id="${db_id%-db}-restore-test"
meta=$(mktemp)
overrides=$(mktemp)

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
  rm -f "$meta" "$overrides"
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
        if [ "$kind" = "backup" ]; then
          aws backup describe-backup-job --backup-job-id "$id" \
            --query StatusMessage --output text --region "$REGION"
        else
          aws backup describe-restore-job --restore-job-id "$id" \
            --query StatusMessage --output text --region "$REGION"
        fi
        return 1
        ;;
    esac
    echo "  $(date '+%H:%M:%S') $state"
    sleep 30
  done
}

# 1. Marcador gravado pela aplicação, como qualquer dado de usuário.
marker="marcador-restauracao-$(date +%s)"
curl -sf -X POST "$app_url/tasks" \
  -H 'Content-Type: application/json' \
  -d "{\"title\":\"$marker\"}" >/dev/null
echo "Marcador gravado no prod às $(date '+%H:%M:%S'): $marker"

# 2. Backup sob demanda, para o ponto conter o marcador.
echo "Backup sob demanda..."
job=$(aws backup start-backup-job \
  --backup-vault-name "$vault" \
  --resource-arn "$db_arn" \
  --iam-role-arn "$role" \
  --query BackupJobId --output text --region "$REGION")
wait_job backup "$job"
rp=$(aws backup describe-backup-job --backup-job-id "$job" \
  --query RecoveryPointArn --output text --region "$REGION")
echo "Ponto de recuperação: $rp"

# 3. Restauração com o mínimo para cair na mesma rede do prod. Repassar
# todos os metadados falha (DBSnapshotIdentifier, campos InformationalOnly)
# e a exportação de logs criaria log groups sem retenção.
aws backup get-recovery-point-restore-metadata \
  --backup-vault-name "$vault" \
  --recovery-point-arn "$rp" \
  --query RestoreMetadata --output json --region "$REGION" \
  | jq --arg id "$restore_id" '{
      DBInstanceIdentifier: $id,
      DBInstanceClass,
      DBSubnetGroupName,
      DBParameterGroupName,
      VpcSecurityGroupIds,
      StorageType,
      MultiAZ: "false",
      PubliclyAccessible: "false",
      DeletionProtection: "false"
    }' > "$meta"

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

restored_host=$(aws rds describe-db-instances --db-instance-identifier "$restore_id" \
  --query 'DBInstances[0].Endpoint.Address' --output text --region "$REGION")
echo "Instância restaurada: $restored_host"

# 4. Task avulsa com a imagem do prod apontando para o banco restaurado.
# O banco é privado; a task usa a rede, o security group e o secret do prod.
network=$(aws ecs describe-services --cluster "$cluster" --services "$service" \
  --query 'services[0].networkConfiguration' --output json --region "$REGION")

check='import sys
from sqlalchemy import text
from db import engine
with engine.connect() as c:
    n = c.execute(text("select count(*) from tasks where title = :t"), {"t": sys.argv[1]}).scalar()
print("MARCADOR_ENCONTRADO" if n else "MARCADOR_AUSENTE")
sys.exit(0 if n else 1)'

jq -n --arg host "$restored_host" --arg code "$check" --arg marker "$marker" '{
  containerOverrides: [{
    name: "app",
    command: ["python", "-c", $code, $marker],
    environment: [{name: "DB_HOST", value: $host}]
  }]
}' > "$overrides"

echo "Procurando o marcador no banco restaurado..."
task=$(aws ecs run-task \
  --cluster "$cluster" \
  --task-definition "$service" \
  --launch-type FARGATE \
  --network-configuration "$network" \
  --overrides "file://$overrides" \
  --query 'tasks[0].taskArn' --output text --region "$REGION")
aws ecs wait tasks-stopped --cluster "$cluster" --tasks "$task" --region "$REGION"
exit_code=$(aws ecs describe-tasks --cluster "$cluster" --tasks "$task" \
  --query 'tasks[0].containers[0].exitCode' --output text --region "$REGION")

echo
echo "RPO: até 24 h, pela frequência do plano diário (o ponto testado foi tirado na hora)"
echo "RTO medido (pedido até a instância disponível): $((rto / 60)) min $((rto % 60)) s"
if [ "$exit_code" = "0" ]; then
  echo "Dados: marcador $marker encontrado no banco restaurado"
else
  echo "Dados: marcador NÃO encontrado (exit $exit_code). Veja o log group /devops-05-prod/app"
  exit 1
fi
