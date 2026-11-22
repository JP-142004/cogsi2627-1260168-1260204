"""Descarrega act e actionlint para a pasta ignorada do laboratório, verificando SHA-256."""
import hashlib
import io
import json
from pathlib import Path
from urllib.request import Request, urlopen
import zipfile

directory = Path(__file__).resolve().parents[1] / 'Part2/.local/tools'
directory.mkdir(parents=True, exist_ok=True)

def download(url):
    with urlopen(Request(url, headers={'User-Agent': 'COGSI-CA5-local-validation'}), timeout=90) as response:
        return response.read()

versions = {}
for repository, asset_name, executable in (
    ('nektos/act', 'act_Windows_x86_64.zip', 'act.exe'),
    ('rhysd/actionlint', None, 'actionlint.exe'),
):
    release = json.loads(download('https://api.github.com/repos/' + repository + '/releases/latest'))
    if asset_name is None:
        asset_name = next(asset['name'] for asset in release['assets'] if asset['name'].endswith('_windows_amd64.zip'))
    asset = next(asset for asset in release['assets'] if asset['name'] == asset_name)
    checksum_asset = next(asset for asset in release['assets'] if 'checksum' in asset['name'].lower() and asset['name'].endswith('.txt'))
    checksums = download(checksum_asset['browser_download_url']).decode()
    matching = [line.split()[0] for line in checksums.splitlines() if line.split()[-1].lstrip('*') == asset_name]
    if len(matching) != 1:
        raise SystemExit('Não foi encontrado um checksum inequívoco para ' + asset_name)
    data = download(asset['browser_download_url'])
    if hashlib.sha256(data).hexdigest().lower() != matching[0].lower():
        raise SystemExit('Checksum incorreto; o executável não foi instalado.')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        member = next(name for name in archive.namelist() if name.rsplit('/', 1)[-1] == executable)
        (directory / executable).write_bytes(archive.read(member))
    versions[executable] = {'version': release['tag_name'], 'sha256': matching[0], 'source': asset['browser_download_url']}
    print(executable + ': ' + release['tag_name'] + ', checksum verificado.')
(directory / 'versions.json').write_text(json.dumps(versions, indent=2) + '\n', encoding='utf-8')
