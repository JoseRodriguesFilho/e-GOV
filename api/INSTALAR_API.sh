#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker nao encontrado."
  exit 1
fi

if [ ! -f .env ]; then
  if command -v openssl >/dev/null 2>&1; then
    CLIENT_TOKEN="$(openssl rand -hex 32)"
    ADMIN_TOKEN="$(openssl rand -hex 32)"
  else
    CLIENT_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
    ADMIN_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
  fi

  cat > .env <<EOF
LAB_API_TOKEN=${CLIENT_TOKEN}
LAB_ADMIN_TOKEN=${ADMIN_TOKEN}
LAB_SEED_CPF=12345678909
LAB_SEED_NAME=Aluno Teste
EOF

  chmod 600 .env
fi

docker compose up -d --build

echo
echo "API iniciada."
echo
echo "Configuracao atual:"
grep -E '^(LAB_API_TOKEN|LAB_ADMIN_TOKEN|LAB_SEED_CPF)=' .env
echo
echo "Teste local:"
echo "  curl http://127.0.0.1:8088/health"
echo
echo "Para HTTPS, publique esta API atras do Caddy/Nginx."
