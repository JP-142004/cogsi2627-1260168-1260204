"""Introduz falhas só no repositório isolado do laboratório e deixa o Poll SCM detetá-las."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('scenario', choices=['unit-failure', 'docker-failure', 'restore'])
args = parser.parse_args()
part = Path(__file__).resolve().parents[1]
local = part / '.local'
scm = local / 'scm.git'
base_file = local / 'scenario-base.json'
environment = os.environ.copy()
environment.update({
    'GIT_DIR': str(scm), 'GIT_INDEX_FILE': str(local / 'scenario.index'),
    'GIT_AUTHOR_NAME': 'CA5 local validation', 'GIT_AUTHOR_EMAIL': 'local@ca5.invalid',
    'GIT_COMMITTER_NAME': 'CA5 local validation', 'GIT_COMMITTER_EMAIL': 'local@ca5.invalid',
})

def git(*arguments, data=None):
    return subprocess.check_output(['git', *arguments], input=data, env=environment)

previous = git('rev-parse', 'refs/heads/development').decode().strip()
if not base_file.exists():
    base_file.write_text(json.dumps({'development': previous}, indent=2) + '\n', encoding='utf-8')
base = json.loads(base_file.read_text(encoding='utf-8'))['development']
git('read-tree', base)
if args.scenario == 'unit-failure':
    path = 'CA5/Part2/bookstore/app/src/test/java/com/example/bookstore/model/ClientTest.java'
    content = git('show', f'{base}:{path}').decode('utf-8')
    old = 'assertEquals("123456789", client.getNif()'
    if content.count(old) != 1:
        raise SystemExit('O teste base mudou; não foi alterado qualquer ficheiro.')
    content = content.replace(old, 'assertEquals("000000000", client.getNif()')
elif args.scenario == 'docker-failure':
    path = 'CA5/Part2/bookstore/Dockerfile'
    content = git('show', f'{base}:{path}').decode('utf-8') + '\n# Falha deliberada, exclusiva desta cópia local de teste.\nRUN exit 17\n'
if args.scenario != 'restore':
    blob = git('hash-object', '-w', '--stdin', data=content.encode('utf-8')).decode().strip()
    git('update-index', '--add', '--cacheinfo', f'100644,{blob},{path}')
tree = git('write-tree').decode().strip()
revision = git('commit-tree', tree, '-p', previous, data=f'CA5 local: {args.scenario}\n'.encode()).decode().strip()
git('update-ref', 'refs/heads/development', revision)
record = {
    'scenario': args.scenario, 'branch': 'development', 'previous': previous,
    'commit': revision, 'created_utc': datetime.now(timezone.utc).isoformat(),
    'trigger': 'Poll SCM; nenhum pedido manual de build foi enviado',
}
(local / ('scenario-' + args.scenario + '.json')).write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
print(json.dumps(record, indent=2))
