#!/usr/bin/env bash
#
# testar-failover.sh
#
# Força o failover do RDS Multi-AZ do prod e mede, pelo CloudFront, quanto
# tempo a aplicação ficou sem banco. Uma requisição por segundo em /ready,
# que só responde 200 quando consegue consultar o banco.
#
# Uso (da raiz do projeto): ./scripts/testar-failover.sh
# Compatível com o bash 3.2 do macOS.

set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
ENV_DIR="terraform/envs/prod"

cd "$(dirname "$0")/.."

app_url=$(terraform -chdir="$ENV_DIR" output -raw app_url)
db_id=$(terraform -chdir="$ENV_DIR" output -raw database_identifier)
log=$(mktemp)

az_of() {
  aws rds describe-db-instances \
    --db-instance-identifier "$db_id" \
    --query 'DBInstances[0].[AvailabilityZone,SecondaryAvailabilityZone,MultiAZ]' \
    --output text \
    --region "$REGION"
}

before=$(az_of)
if [ "$(printf '%s' "$before" | awk '{print $3}')" != "True" ]; then
  echo "A instância $db_id não é Multi-AZ; o teste não se aplica."
  exit 1
fi

probe() {
  while :; do
    code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "$app_url/ready" || true)
    echo "$(date +%s) $code" >> "$log"
    sleep 1
  done
}

probe &
probe_pid=$!
trap 'kill "$probe_pid" 2>/dev/null || true' EXIT

echo "Aplicação: $app_url"
echo "Antes: primária $(printf '%s' "$before" | awk '{print $1}'), standby $(printf '%s' "$before" | awk '{print $2}')"
echo "Linha de base de 10 s..."
sleep 10

started=$(date +%s)
echo "Forçando o failover às $(date '+%H:%M:%S')..."
aws rds reboot-db-instance --db-instance-identifier "$db_id" --force-failover \
  --region "$REGION" >/dev/null

sleep 20
aws rds wait db-instance-available --db-instance-identifier "$db_id" --region "$REGION"
echo "Instância disponível de novo após $(($(date +%s) - started)) s. Observando mais 60 s..."
sleep 60

kill "$probe_pid" 2>/dev/null || true
wait "$probe_pid" 2>/dev/null || true
after=$(az_of)

# Maior sequência de respostas diferentes de 200, em segundos.
summary=$(awk -v start="$started" '
  $1 >= start {
    total++
    if ($2 != "200") {
      fail++
      if (run == 0) run_start = $1
      run++
      last = $1
      if (last - run_start + 1 > longest) longest = last - run_start + 1
    } else {
      run = 0
    }
  }
  END { printf "%d %d %d", total, fail, longest }
' "$log")

total=$(printf '%s' "$summary" | awk '{print $1}')
fail=$(printf '%s' "$summary" | awk '{print $2}')
longest=$(printf '%s' "$summary" | awk '{print $3}')

echo
echo "Depois: primária $(printf '%s' "$after" | awk '{print $1}'), standby $(printf '%s' "$after" | awk '{print $2}')"
echo "Requisições desde o failover: $total · com erro: $fail"
echo "Maior janela sem banco vista pela aplicação: ${longest} s"
echo "Log completo (epoch e código HTTP): $log"
