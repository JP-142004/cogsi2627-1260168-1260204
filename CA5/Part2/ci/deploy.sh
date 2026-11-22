#!/usr/bin/env bash
set -eu

mode="${1:?Indica deploy ou verify}"
case "$mode" in
  deploy|verify) ;;
  *) echo 'Playbook não suportado.' >&2; exit 2 ;;
esac

: "${SSH_KEY:?A chave SSH tem de ser fornecida pelo gestor de credenciais}"
: "${BOOKSTORE_IMAGE_REPOSITORY:?Indica o repositório da imagem}"
: "${BOOKSTORE_IMAGE_TAG:?Indica a tag da imagem}"

part="${PART_DIR:-CA5/Part2}"
exec ansible-playbook -i "$part/ansible/hosts.ini" "$part/ansible/$mode.yml" \
  --private-key "$SSH_KEY" \
  -e "ansible_host=${PRODUCTION_HOST:-192.168.56.20}" \
  -e "ansible_port=${PRODUCTION_SSH_PORT:-22}"
