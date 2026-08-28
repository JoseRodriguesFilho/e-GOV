#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f .env ]; then
  echo ".env nao existe. Execute ./INSTALAR_API.sh"
  exit 1
fi
grep -E '^(LAB_API_TOKEN|LAB_ADMIN_TOKEN|LAB_SEED_CPF|LAB_SEED_NAME)=' .env
