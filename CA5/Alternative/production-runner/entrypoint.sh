#!/usr/bin/env bash
set -eu
cd /home/runner
if [ ! -s /run/secrets/registration_token ]; then
  echo 'É necessário um token de registo do runner emitido pelo administrador.' >&2
  exit 1
fi
if [ ! -r "${CA5_LOCAL_SSH_KEY:-}" ]; then
  echo 'A chave SSH local da VM não está montada.' >&2
  exit 1
fi
./config.sh --unattended --ephemeral --disableupdate \
  --url https://github.com/JP-142004/cogsi2627-1260168-1260204 \
  --token "$(cat /run/secrets/registration_token)" \
  --name ca5-production-local --labels ca5-production --work _work
exec ./run.sh
