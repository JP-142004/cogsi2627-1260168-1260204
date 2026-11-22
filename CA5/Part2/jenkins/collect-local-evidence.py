"""Resume resultados observados do laboratório; não exporta segredos nem configurações privadas."""
import base64
import json
from pathlib import Path
from urllib.request import Request, urlopen

part = Path(__file__).resolve().parents[1]
evidence = part / 'evidence'
local = part / '.local'
cases = []
for prefix, branch, number, expected in (
    ('19-jenkins-success', 'main', 2, 'SUCCESS'),
    ('20-jenkins-success', 'development', 2, 'SUCCESS'),
    ('23-jenkins-unstable-email', 'development', 4, 'UNSTABLE'),
    ('24-jenkins-docker-failure', 'development', 5, 'FAILURE'),
    ('25-jenkins-recovery', 'development', 6, 'SUCCESS'),
):
    name = f'{prefix}-{branch}-{number}'
    data = json.loads((evidence / (name + '.json')).read_text(encoding='utf-8'))
    if data['result'] != expected or data['building']:
        raise SystemExit('Resultado inesperado no caso ' + name)
    causes = [cause['shortDescription'] for action in data['actions'] for cause in action.get('causes', [])]
    stages = json.loads((evidence / (name + '-stages.json')).read_text(encoding='utf-8'))['stages']
    cases.append({'branch': branch, 'build': number, 'result': data['result'], 'causes': causes,
                  'stages': [{'name': stage['name'], 'status': stage['status']} for stage in stages]})

intervals = {}
for task in ('test', 'integrationTest'):
    intervals[task] = json.loads((evidence / f'19-jenkins-success-main-2-{task}-timing.json').read_text(encoding='utf-8'))
overlap = min(value['finished_epoch'] for value in intervals.values()) - max(value['started_epoch'] for value in intervals.values())
if overlap <= 0:
    raise SystemExit('Os intervalos dos dois testes não se sobrepõem.')
before = (local / 'production-before-scenarios.txt').read_text(encoding='utf-8-sig').strip()
after = (local / 'production-after-scenarios.txt').read_text(encoding='utf-8-sig').strip()
if before != after:
    raise SystemExit('A produção mudou durante os cenários da development.')

with urlopen('http://127.0.0.1:18025/api/v1/messages', timeout=15) as response:
    messages = json.load(response)['messages']
notifications = []
for message in messages:
    if 'ca5-local/' not in message['Subject']:
        continue
    with urlopen('http://127.0.0.1:18025/api/v1/message/' + message['ID'], timeout=15) as response:
        detail = json.load(response)
    notifications.append({'subject': message['Subject'], 'created': message['Created'], 'text': detail.get('Text', '')})
for result in ('SUCCESS', 'FAILURE', 'UNSTABLE'):
    if not any('CA5 ' + result + ':' in message['subject'] for message in notifications):
        raise SystemExit('Não foi recebida a notificação ' + result)

password = (local / 'secrets/registry_password').read_text(encoding='utf-8').strip()
authorization = base64.b64encode(('ca5-local:' + password).encode()).decode()
request = Request('http://127.0.0.1:15000/v2/luizbsilv/ca5-bookstore/tags/list', headers={'Authorization': 'Basic ' + authorization})
with urlopen(request, timeout=15) as response:
    tags = json.load(response)['tags']
for blocked in ('jenkins-development-3-', 'jenkins-development-4-', 'jenkins-development-5-'):
    if any(tag.startswith(blocked) for tag in tags):
        raise SystemExit('Foi publicada uma imagem de um build que devia estar bloqueado.')
summary = {
    'scope': 'laboratório local; repositório SCM e registo de imagens locais',
    'cases': cases, 'parallel_intervals': intervals, 'parallel_overlap_seconds': round(overlap, 3),
    'production_unchanged_during_development_cases': True, 'production_container': before,
    'notifications': notifications, 'registry_tags': tags,
    'github_writes': False,
}
(evidence / '26-local-validation-summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Validados: cinco execuções, testes sobrepostos, três tipos de e-mail e produção preservada na development.')
