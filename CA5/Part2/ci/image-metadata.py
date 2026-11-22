"""Arquiva apenas dados de rastreabilidade; nunca lê credenciais."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
from datetime import datetime, timezone

part = Path(os.environ.get('PART_DIR', 'CA5/Part2'))
artifact = part / 'bookstore/app/build/libs/app-1.0.0.jar'
destination = Path('dist')
destination.mkdir(exist_ok=True)
shutil.copyfile(part / 'bookstore/Dockerfile', destination / 'Dockerfile')
image = os.environ['IMAGE_REFERENCE']
image_id = subprocess.check_output(['docker', 'image', 'inspect', '--format', '{{.Id}}', image], text=True).strip()
metadata = {
    'provider': os.environ.get('CI_PROVIDER', 'jenkins'),
    'image': image,
    'image_id': image_id,
    'tag': os.environ['BOOKSTORE_IMAGE_TAG'],
    'commit': os.environ['SOURCE_COMMIT'],
    'branch': os.environ['SOURCE_BRANCH'],
    'build': os.environ['CI_BUILD_NUMBER'],
    'created_utc': datetime.now(timezone.utc).isoformat(),
    'jar_sha256': hashlib.sha256(artifact.read_bytes()).hexdigest(),
}
(destination / 'build.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
print(f'Metadados arquivados para {image}.')
