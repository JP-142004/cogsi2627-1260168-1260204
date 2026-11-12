"""Prepara segredos e refs de teste locais; não contacta o GitHub."""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--refresh-scm', action='store_true', help='Criar um snapshot dos ficheiros locais e atualizar as refs de teste')
args = parser.parse_args()
part = Path(__file__).resolve().parents[1]
repository = part.parents[1]
local = part / '.local'
secret_directory = local / 'secrets'
secret_directory.mkdir(parents=True, exist_ok=True)
for filename in ('admin_password', 'registry_password'):
    target = secret_directory / filename
    if not target.exists():
        target.write_text(secrets.token_urlsafe(32) + '\n', encoding='utf-8')

key = part / '.vagrant/machines/production/virtualbox/private_key'
if not key.is_file():
    raise SystemExit('Arranca primeiro a VM production com Vagrant para gerar a chave SSH.')
shutil.copyfile(key, secret_directory / 'production_key')

password_file = secret_directory / 'registry.htpasswd'
if not password_file.exists():
    password = (secret_directory / 'registry_password').read_text(encoding='utf-8').strip()
    hashed = subprocess.run(
        ['docker', 'run', '--rm', '-i', '--entrypoint', 'htpasswd', 'cogsi-ca5-jenkins:local', '-Bni', 'ca5-local'],
        input=password + '\n', capture_output=True, text=True, check=True,
    )
    password_file.write_text(hashed.stdout, encoding='utf-8')

scm = local / 'scm.git'
if not scm.exists():
    subprocess.run(['git', 'init', '--bare', str(scm)], check=True)
    args.refresh_scm = True
if args.refresh_scm:
    # Um índice independente permite testar a árvore de trabalho sem fazer commits prematuros na branch do aluno.
    files = subprocess.check_output(['git', '-C', str(repository), 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', 'CA5/Part2', '.github/workflows/ca5-bookstore.yml'])
    environment = os.environ.copy()
    environment.update({
        'GIT_DIR': str(scm), 'GIT_WORK_TREE': str(repository),
        'GIT_INDEX_FILE': str(local / 'snapshot.index'),
        'GIT_AUTHOR_NAME': 'CA5 local validation', 'GIT_AUTHOR_EMAIL': 'local@ca5.invalid',
        'GIT_COMMITTER_NAME': 'CA5 local validation', 'GIT_COMMITTER_EMAIL': 'local@ca5.invalid',
    })
    subprocess.run(['git', 'read-tree', '--empty'], env=environment, check=True)
    subprocess.run(['git', '-c', 'core.autocrlf=false', 'add', '--pathspec-from-file=-', '--pathspec-file-nul'], input=files, env=environment, cwd=repository, check=True)
    tree = subprocess.check_output(['git', 'write-tree'], env=environment, text=True).strip()
    parent = subprocess.run(['git', 'rev-parse', '--verify', 'refs/heads/main'], env=environment, text=True, capture_output=True)
    command = ['git', 'commit-tree', tree]
    if parent.returncode == 0:
        command += ['-p', parent.stdout.strip()]
    revision = subprocess.check_output(command, input='Snapshot para validacao local do CA5\n', env=environment, text=True).strip()
    subprocess.run(['git', '--git-dir', str(scm), 'update-ref', 'refs/heads/main', revision], check=True)
    subprocess.run(['git', '--git-dir', str(scm), 'update-ref', 'refs/heads/development', revision], check=True)
    subprocess.run(['git', '--git-dir', str(scm), 'symbolic-ref', 'HEAD', 'refs/heads/main'], check=True)
    source_head = subprocess.check_output(['git', '-C', str(repository), 'rev-parse', 'HEAD'], text=True).strip()
    (local / 'source-manifest.json').write_text(json.dumps({'local_snapshot': revision, 'source_head': source_head, 'includes_working_tree': True}, indent=2) + '\n', encoding='utf-8')
    (local / 'scenario-base.json').write_text(json.dumps({'development': revision}, indent=2) + '\n', encoding='utf-8')
print('Segredos locais preparados e chave copiada; nenhum valor secreto foi mostrado.')
print('Repositório de teste: CA5/Part2/.local/scm.git (sem ligação de escrita ao GitHub).')
