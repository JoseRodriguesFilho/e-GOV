#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [ $# -lt 2 ]; then
  echo "Uso: $0 CPF \"Nome do aluno\""
  exit 1
fi

CPF="$1"
NAME="$2"
source ./.env

curl -fsS -X POST "http://127.0.0.1:8088/admin/students" \
  -H "Content-Type: application/json" \
  -H "X-Admin-Token: ${LAB_ADMIN_TOKEN}" \
  -d "{\"cpf\":\"${CPF}\",\"name\":\"${NAME}\",\"active\":true}"

echo
