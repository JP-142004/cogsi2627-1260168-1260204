"""Autenticação por stdin, configuração temporária e push da imagem construída."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import urlsplit

registry = os.environ.get('DOCKER_REGISTRY_URL', 'https://index.docker.io/v1/')
parsed = urlsplit(registry)
if parsed.scheme not in ('https', 'http') or not parsed.hostname or parsed.username or parsed.password:
    raise SystemExit('URL de registo inválido.')
if parsed.scheme == 'http' and parsed.hostname not in ('localhost', '127.0.0.1', '::1'):
    raise SystemExit('HTTP só é permitido no registo de teste em loopback.')
image = os.environ['IMAGE_REFERENCE']
username = os.environ['DOCKERHUB_USERNAME']
token = os.environ['DOCKERHUB_TOKEN']
if not username or not token:
    raise SystemExit('As credenciais do registo estão ausentes.')

temporary_parent = Path('.ci')
temporary_parent.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='docker-auth-', dir=temporary_parent) as config:
    command = ['docker', '--config', str(Path(config).resolve())]
    subprocess.run(command + ['login', registry, '--username', username, '--password-stdin'],
                   input=token + '\n', text=True, check=True)
    subprocess.run(command + ['push', image], check=True)
digests = json.loads(subprocess.check_output(['docker', 'image', 'inspect', '--format', '{{json .RepoDigests}}', image], text=True))
Path('dist').mkdir(exist_ok=True)
Path('dist/push.json').write_text(json.dumps({'image': image, 'repo_digests': digests}, indent=2) + '\n', encoding='utf-8')
