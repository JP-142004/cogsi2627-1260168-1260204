"""Recolhe uma execução real da ca5-part2; preserva falhas e valida artefactos."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess
import tarfile
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('run_id')
args = parser.parse_args()
repo = 'JP-142004/cogsi2627-1260168-1260204'
alternative = Path(__file__).resolve().parent
local = alternative.parent / 'Part2/.local/github-artifacts' / args.run_id
local.mkdir(parents=True, exist_ok=True)
evidence = alternative / 'evidence'
prefix = '06-github-' + args.run_id

def gh(*arguments):
    return subprocess.check_output(['gh', *arguments], text=True, encoding='utf-8')

record = json.loads(gh('run', 'view', args.run_id, '-R', repo, '--json', 'databaseId,headSha,headBranch,event,status,conclusion,url,jobs,createdAt,updatedAt'))
if record['status'] != 'completed' or record['headBranch'] != 'ca5-part2':
    raise SystemExit('É necessária uma execução concluída da ca5-part2.')
jobs = {job['name']: job for job in record['jobs']}
required = ('Assemble', 'Tests (test)', 'Tests (integrationTest)', 'Build, archive and push image')
if any(jobs[name]['conclusion'] != 'success' for name in required):
    raise SystemExit('Compilação, testes ou publicação não passaram; consulta a execução antes de consolidar.')
if jobs['Deploy and verify production']['conclusion'] != 'skipped':
    raise SystemExit('O deploy não foi ignorado na branch de trabalho.')
for artifact in ('prepared-app', 'junit-test', 'junit-integrationTest', 'build-metadata', 'published-image'):
    destination = local / artifact
    if not destination.exists():
        subprocess.run(['gh', 'run', 'download', args.run_id, '-R', repo, '-n', artifact, '-D', str(destination)], check=True)
metadata = json.loads(next((local / 'build-metadata').rglob('build.json')).read_text(encoding='utf-8'))
push = json.loads(next((local / 'published-image').rglob('push.json')).read_text(encoding='utf-8'))
assert metadata['commit'] == record['headSha'] and metadata['branch'] == 'ca5-part2'
assert push['image'] == metadata['image']
with tarfile.open(next((local / 'prepared-app').rglob('prepared-app.tgz')), 'r:gz') as package:
    jar = package.extractfile('app/build/libs/app-1.0.0.jar').read()
assert hashlib.sha256(jar).hexdigest() == metadata['jar_sha256']
reports = {}
for task in ('test', 'integrationTest'):
    total = {key: 0 for key in ('tests', 'failures', 'errors', 'skipped')}
    for path in (local / ('junit-' + task)).rglob('*.xml'):
        suite = ET.fromstring(path.read_bytes())
        for key in total:
            total[key] += int(suite.get(key, 0))
    reports[task] = total
assert sum(report['tests'] for report in reports.values()) == 3
assert sum(report['failures'] + report['errors'] for report in reports.values()) == 0
remote = json.loads(subprocess.check_output(['docker', 'buildx', 'imagetools', 'inspect', metadata['image'], '--format', '{{json .Manifest}}'], text=True))
assert any(value.endswith('@' + remote['digest']) for value in push['repo_digests'])
record.update({'provider': 'github-actions', 'junit': reports, 'jar_matches_prepared_artifact': True,
               'build_metadata': metadata, 'published_image': push, 'dockerhub_manifest_digest': remote['digest'],
               'deploy_skipped': True, 'email_delivered': False,
               'email_limitation': 'Autorização SMTP Microsoft 365 ainda não configurada; não se considera o run inteiramente bem-sucedido.'})
(evidence / (prefix + '.json')).write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
logs = gh('run', 'view', args.run_id, '-R', repo, '--log')
logs = re.sub(r'\b[0-9]+@isep\.ipp\.pt\b', '<email ISEP configurado>', logs)
(evidence / (prefix + '.txt')).write_text('\n'.join(line.rstrip() for line in logs.splitlines()).rstrip() + '\n', encoding='utf-8', newline='\n')
print(json.dumps({'run': record['url'], 'conclusion': record['conclusion'], 'image': metadata['image'],
                  'junit': reports, 'jar_integrity': True, 'dockerhub_digest_verified': True,
                  'deploy': 'skipped', 'email': jobs['Email notification']['conclusion']}, ensure_ascii=False, indent=2))
