"""Executa o workflow com act numa cópia isolada e serviços exclusivamente locais."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
parser = argparse.ArgumentParser()
parser.add_argument('--branch', choices=['main', 'development'], default='development')
parser.add_argument('--job', help='Executar um job específico do workflow')
parser.add_argument('--list', action='store_true')
parser.add_argument('--scenario', choices=['success', 'unit-failure'], default='success')
args = parser.parse_args()
alternative = Path(__file__).resolve().parent
ca5 = alternative.parent
repository = ca5.parent
local = ca5 / 'Part2/.local'
run_id = str(int(time.time()))
worktree = local / ('actions-' + args.branch)
configuration = local / 'actions-config' / args.branch
artifacts = local / 'actions-artifacts' / args.branch / run_id
for directory in (worktree, configuration, artifacts, alternative / 'evidence'):
    directory.mkdir(parents=True, exist_ok=True)

files = subprocess.check_output([
    'git', '-C', str(repository), 'ls-files', '-z', '--cached', '--others', '--exclude-standard',
    '--', '.gitignore', '.github/workflows/ca5-bookstore.yml', '.github/actionlint.yaml', 'CA5/Part2', 'CA5/Alternative',
]).decode('utf-8').strip('\0').split('\0')
for filename in files:
    source = repository / filename
    if not source.is_file():
        continue
    destination = worktree / filename
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
if args.scenario == 'unit-failure':
    target = worktree / 'CA5/Part2/bookstore/app/src/test/java/com/example/bookstore/model/ClientTest.java'
    content = target.read_text(encoding='utf-8')
    original = 'assertEquals("123456789", client.getNif()'
    if content.count(original) != 1:
        raise SystemExit('O teste base mudou; cenário não aplicado.')
    target.write_text(content.replace(original, 'assertEquals("000000000", client.getNif()'), encoding='utf-8')
if not (worktree / '.git').is_dir():
    subprocess.run(['git', 'init', '-b', args.branch, str(worktree)], check=True)
    subprocess.run(['git', '-C', str(worktree), 'config', 'user.name', 'CA5 act validation'], check=True)
    subprocess.run(['git', '-C', str(worktree), 'config', 'user.email', 'act@ca5.invalid'], check=True)
    subprocess.run(['git', '-C', str(worktree), 'remote', 'add', 'origin', 'https://github.com/JP-142004/cogsi2627-1260168-1260204.git'], check=True)
subprocess.run(['git', '-C', str(worktree), '-c', 'core.autocrlf=false', 'add', '--all'], check=True)
subprocess.run(['git', '-C', str(worktree), 'commit', '--allow-empty', '-m', 'CA5 act: snapshot local de validacao'], check=True, stdout=subprocess.DEVNULL)
revision = subprocess.check_output(['git', '-C', str(worktree), 'rev-parse', 'HEAD'], text=True).strip()
event = {
    'ref': 'refs/heads/' + args.branch, 'after': revision, 'head_commit': {'id': revision},
    'repository': {'full_name': 'JP-142004/cogsi2627-1260168-1260204', 'name': 'cogsi2627-1260168-1260204',
                   'owner': {'login': 'JP-142004', 'name': 'JP-142004'}, 'default_branch': 'main',
                   'html_url': 'https://github.com/JP-142004/cogsi2627-1260168-1260204'},
    'sender': {'login': 'ca5-local'},
}
(configuration / 'event.json').write_text(json.dumps(event), encoding='utf-8')
password = (local / 'secrets/registry_password').read_text(encoding='utf-8').strip()
key = (local / 'secrets/production_key').read_text(encoding='utf-8')
local_secrets = {'DOCKERHUB_USERNAME': 'ca5-local', 'DOCKERHUB_TOKEN': password, 'CA5_PRODUCTION_SSH_KEY': key}
(configuration / 'secrets.env').write_text(''.join(name + '=' + json.dumps(value) + '\n' for name, value in local_secrets.items()), encoding='utf-8')
ssh_port = subprocess.check_output(['vagrant', 'port', 'production', '--guest', '22'], cwd=ca5 / 'Part2', text=True).strip()
variables = {
    'CA5_IMAGE_REPOSITORY': 'localhost:15000/luizbsilv/ca5-bookstore',
    'CA5_REGISTRY_URL': 'http://localhost:15000',
    'CA5_PRODUCTION_HOST': 'host.docker.internal', 'CA5_PRODUCTION_SSH_PORT': ssh_port,
    'SMTP_HOST': 'host.docker.internal', 'SMTP_PORT': '11025',
    'SMTP_STARTTLS': 'false', 'SMTP_SSL': 'false',
    'NOTIFY_FROM': 'actions@ca5.local', 'NOTIFY_TO': 'luiz@ca5.local',
}
(configuration / 'vars.env').write_text(''.join(name + '=' + value + '\n' for name, value in variables.items()), encoding='utf-8')
# O runner local já tem Python 3.13. Regista o intérprete real na cache do act
# para que setup-python o encontre sem pedir um binário Ubuntu para Debian.
cache_setup = 'version="$(/usr/bin/python3 -c \'import sys; print(".".join(map(str, sys.version_info[:3])))\')"; directory="/opt/hostedtoolcache/Python/$version"; mkdir -p "$directory"; if [ ! -e "$directory/x64/bin/python3" ]; then ln -s /usr "$directory/x64"; fi; touch "$directory/x64.complete"'
subprocess.run(['docker', 'run', '--rm', '-v', 'act-toolcache:/opt/hostedtoolcache', '--entrypoint', 'bash', 'cogsi-ca5-actions-runner:local', '-c', cache_setup], check=True)
command = [
    str(local / 'tools/act.exe'), 'push', '-C', str(worktree), '-W', '.github/workflows/ca5-bookstore.yml',
    '-e', str(configuration / 'event.json'), '--secret-file', str(configuration / 'secrets.env'),
    '--var-file', str(configuration / 'vars.env'),
    '-P', 'ubuntu-latest=cogsi-ca5-actions-runner:local',
    '-P', 'self-hosted=cogsi-ca5-actions-runner:local',
    '-P', 'ca5-production=cogsi-ca5-actions-runner:local',
    '--pull=false', '--concurrent-jobs=1', '--container-daemon-socket', '/var/run/docker.sock',
    '--rm',
    '--container-options', '--memory=1536m -v cogsi-ca5-local_gradle-cache:/root/.gradle',
    '--network', 'cogsi-ca5-local_default', '--artifact-server-path', str(artifacts),
    '--artifact-server-port', '34567' if args.branch == 'main' else '34568',
    '--action-cache-path', str(local / 'actions-cache'), '--no-cache-server',
    '--env', 'GITHUB_RUN_ID=' + run_id, '--env', 'GITHUB_RUN_NUMBER=1',
    '--env', 'GITHUB_RUN_ATTEMPT=1', '--env', 'GITHUB_SHA=' + revision,
    '--env', 'GITHUB_REF=refs/heads/' + args.branch,
    '--env', 'GITHUB_REF_NAME=' + args.branch,
    '--env', 'ACTIONS_ARTIFACT_UPLOAD_CONCURRENCY=1',
]
if args.job:
    command += ['--job', args.job]
if args.list:
    command += ['--list']
    raise SystemExit(subprocess.run(command).returncode)
audit_command = "sudo docker inspect --format '{{.Id}} {{.Config.Image}} {{.State.Health.Status}}' ca5-bookstore"
production_before = subprocess.check_output(['vagrant', 'ssh', 'production', '-c', audit_command], cwd=ca5 / 'Part2', text=True).strip()
prefix = '01-act-' + args.branch if args.scenario == 'success' else '02-act-' + args.branch + '-' + args.scenario
with (alternative / 'evidence' / (prefix + '.txt')).open('w', encoding='utf-8') as output:
    result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=False)
production_after = subprocess.check_output(['vagrant', 'ssh', 'production', '-c', audit_command], cwd=ca5 / 'Part2', text=True).strip()
record = {
    'provider': 'act-local-emulation', 'branch': args.branch, 'commit': revision,
    'scenario': args.scenario,
    'run_id': run_id, 'exit_code': result.returncode, 'finished_utc': datetime.now(timezone.utc).isoformat(),
    'registry': variables['CA5_REGISTRY_URL'], 'github_writes': False,
    'concurrent_jobs_in_emulation': 1,
    'artifact_directory': artifacts.relative_to(local).as_posix(),
    'production_before': production_before,
    'production_after': production_after,
    'production_changed': production_before != production_after,
}
(alternative / 'evidence' / (prefix + '.json')).write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
print(json.dumps(record, indent=2))
if args.branch == 'development' and result.returncode == 0 and production_before != production_after:
    raise SystemExit('A development alterou a produção; consultar as evidências.')
raise SystemExit(result.returncode)
