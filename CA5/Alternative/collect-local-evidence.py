"""Verifica resultados, JUnit, artefactos e e-mails das execuções locais registadas."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile
from urllib.request import urlopen
import xml.etree.ElementTree as ET
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--include-failure', action='store_true')
args = parser.parse_args()
alternative = Path(__file__).resolve().parent
local = alternative.parent / 'Part2/.local'
evidence = alternative / 'evidence'
cases = [('main', '01-act-main', False), ('development', '01-act-development', False)]
if args.include_failure:
    cases.append(('development', '02-act-development-unit-failure', True))
summary = []

with urlopen('http://127.0.0.1:18025/api/v1/messages', timeout=15) as response:
    messages = json.load(response)['messages']
emails = []
for message in messages:
    if 'GitHub Actions' not in message['Subject']:
        continue
    with urlopen('http://127.0.0.1:18025/api/v1/message/' + message['ID'], timeout=15) as response:
        detail = json.load(response)
    emails.append({'subject': message['Subject'], 'text': detail.get('Text', ''), 'created': message['Created']})

for branch, prefix, expected_failure in cases:
    record = json.loads((evidence / (prefix + '.json')).read_text(encoding='utf-8'))
    if (record['exit_code'] != 0) != expected_failure:
        raise SystemExit('Resultado inesperado na execução ' + prefix)
    root = local / record.get('artifact_directory', 'actions-artifacts/' + branch)

    def artifact(name):
        matches = [path for path in root.rglob(name + '.zip') if record['run_id'] in path.parts]
        if len(matches) != 1:
            raise SystemExit('Artefacto ausente ou ambíguo: ' + name)
        archive = zipfile.ZipFile(matches[0])
        if archive.testzip() is not None:
            raise SystemExit('CRC inválido no artefacto ' + name)
        return archive

    reports = {}
    timings = {}
    for task in ('test', 'integrationTest'):
        archive = artifact('junit-' + task)
        totals = {key: 0 for key in ('tests', 'failures', 'errors', 'skipped')}
        for filename in archive.namelist():
            if filename.endswith('.xml'):
                suite = ET.fromstring(archive.read(filename))
                for key in totals:
                    totals[key] += int(suite.get(key, 0))
            elif filename.endswith(task + '-timing.json'):
                timings[task] = json.loads(archive.read(filename))
        reports[task] = totals
    failed = sum(value['failures'] + value['errors'] for value in reports.values())
    if (failed > 0) != expected_failure:
        raise SystemExit('Os XML JUnit não confirmam o cenário esperado.')
    if sum(value['tests'] for value in reports.values()) != 3:
        raise SystemExit('Não foram encontrados os três testes esperados.')

    metadata = None
    if not expected_failure:
        archive = artifact('build-metadata')
        name = next(name for name in archive.namelist() if name.rsplit('/', 1)[-1] == 'build.json')
        metadata = json.loads(archive.read(name))
        if metadata['commit'] != record['commit'] or metadata['branch'] != branch:
            raise SystemExit('Commit ou branch dos metadados não corresponde à execução.')
        prepared = artifact('prepared-app')
        with tarfile.open(fileobj=io.BytesIO(prepared.read('prepared-app.tgz')), mode='r:gz') as package:
            jar = package.extractfile('app/build/libs/app-1.0.0.jar').read()
        if hashlib.sha256(jar).hexdigest() != metadata['jar_sha256']:
            raise SystemExit('O JAR usado na imagem não corresponde ao artefacto preparado.')
        published = artifact('published-image')
        push_name = next(name for name in published.namelist() if name.rsplit('/', 1)[-1] == 'push.json')
        push = json.loads(published.read(push_name))
        if push['image'] != metadata['image']:
            raise SystemExit('A referência publicada não corresponde à imagem construída.')
        (evidence / (prefix + '-build.json')).write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
        (evidence / (prefix + '-push.json')).write_text(json.dumps(push, indent=2) + '\n', encoding='utf-8')
    elif list(root.rglob('published-image.zip')) or list(root.rglob('build-metadata.zip')):
        raise SystemExit('A versão com testes falhados chegou à construção ou publicação da imagem.')

    expected_status = 'FAILURE' if expected_failure else 'SUCCESS'
    notifications = [email for email in emails if record['commit'] in email['text'] and 'CA5 ' + expected_status + ':' in email['subject']]
    if not notifications:
        raise SystemExit('Não foi recebida a notificação correspondente a ' + prefix)
    if branch == 'development' and record.get('production_changed'):
        raise SystemExit('A development alterou a produção.')
    overlap = min(value['finished_epoch'] for value in timings.values()) - max(value['started_epoch'] for value in timings.values()) if len(timings) == 2 else None
    summary.append({
        'case': prefix, 'branch': branch, 'run_id': record['run_id'], 'exit_code': record['exit_code'],
        'expected_failure': expected_failure, 'junit': reports, 'timings': timings,
        'timing_overlap_seconds': round(overlap, 3) if overlap is not None else None,
        'jar_hash_matches_prepared_artifact': True if metadata is not None else None,
        'image': metadata['image'] if metadata else None,
        'production_changed': record.get('production_changed'), 'notifications': notifications,
    })
(evidence / '03-local-validation-summary.json').write_text(json.dumps({'scope': 'act local; não é uma execução do serviço GitHub', 'cases': summary}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Validados resultados JUnit, integridade dos artefactos, rastreabilidade e notificações das execuções locais.')
