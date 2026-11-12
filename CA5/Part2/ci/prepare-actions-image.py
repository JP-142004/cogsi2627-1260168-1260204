"""Define a tag única e os outputs da alternativa GitHub Actions."""
import os
from pathlib import Path
import re

branch = os.environ.get('GITHUB_REF_NAME') or os.environ['GITHUB_REF'].removeprefix('refs/heads/')
slug = re.sub(r'[^a-z0-9_.-]', '-', branch.lower())[:40]
commit = os.environ['GITHUB_SHA']
tag = f"gha-{slug}-{os.environ['GITHUB_RUN_ID']}-{os.environ.get('GITHUB_RUN_ATTEMPT', '1')}-{commit[:7]}"
repository = os.environ['BOOKSTORE_IMAGE_REPOSITORY']
values = {
    'BOOKSTORE_IMAGE_TAG': tag, 'IMAGE_REFERENCE': f'{repository}:{tag}',
    'SOURCE_COMMIT': commit, 'SOURCE_BRANCH': branch,
    'CI_BUILD_NUMBER': f"{os.environ['GITHUB_RUN_NUMBER']}.{os.environ.get('GITHUB_RUN_ATTEMPT', '1')}",
    'CI_PROVIDER': 'github-actions',
}
if any('\n' in value or '\r' in value for value in values.values()):
    raise SystemExit('Metadados de imagem inválidos.')
with Path(os.environ['GITHUB_ENV']).open('a', encoding='utf-8') as output:
    for name, value in values.items():
        output.write(f'{name}={value}\n')
with Path(os.environ['GITHUB_OUTPUT']).open('a', encoding='utf-8') as output:
    output.write(f"image={values['IMAGE_REFERENCE']}\ntag={tag}\n")
print(f"Imagem desta execução: {values['IMAGE_REFERENCE']}")
