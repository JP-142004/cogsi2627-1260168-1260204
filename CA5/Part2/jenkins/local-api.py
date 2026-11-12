"""Cliente de administração do Jenkins local; credenciais lidas só em memória."""
import argparse
import base64
import http.cookiejar
import json
import sys
from pathlib import Path
from urllib.parse import urlencode, quote
from urllib.request import HTTPCookieProcessor, Request, build_opener
from urllib.error import HTTPError

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

part = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('operation', choices=['status', 'scan', 'build', 'logs', 'lint', 'export'])
parser.add_argument('--branch', default='main')
parser.add_argument('--number', default='lastBuild')
parser.add_argument('--prefix', default='19-jenkins')
args = parser.parse_args()
password = (part / '.local/secrets/admin_password').read_text(encoding='utf-8').strip()
authorization = 'Basic ' + base64.b64encode(('luiz:' + password).encode()).decode()
opener = build_opener(HTTPCookieProcessor(http.cookiejar.CookieJar()))
base = 'http://127.0.0.1:18080/'

def request(path, data=None, content_type=None):
    headers = {'Authorization': authorization}
    if data is not None:
        crumb = json.loads(request('crumbIssuer/api/json'))
        headers[crumb['crumbRequestField']] = crumb['crumb']
    if content_type:
        headers['Content-Type'] = content_type
    return opener.open(Request(base + path, data=data, headers=headers), timeout=45).read()

job = 'job/ca5-local/'
build = job + 'job/' + quote(args.branch, safe='') + '/' + args.number + '/'
try:
    if args.operation == 'status':
        tree = 'name,jobs[name,color,lastBuild[number,result,building,duration,timestamp]],indexing[building,result]'
        print(request(job + 'api/json?' + urlencode({'tree': tree})).decode())
    elif args.operation == 'scan':
        request(job + 'build?delay=0sec', b'')
        print('Indexação local pedida.')
    elif args.operation == 'build':
        request(job + 'job/' + quote(args.branch, safe='') + '/buildWithParameters?delay=0sec', b'')
        print('Execução local pedida para ' + args.branch + '.')
    elif args.operation == 'logs':
        print(request(build + 'consoleText').decode(errors='replace')[-18000:])
    elif args.operation == 'lint':
        data = urlencode({'jenkinsfile': (part / 'Jenkinsfile').read_text(encoding='utf-8')}).encode()
        result = request('pipeline-model-converter/validate', data, 'application/x-www-form-urlencoded').decode()
        print(result)
        if 'successfully validated' not in result:
            raise SystemExit(1)
    else:
        evidence = part / 'evidence'
        snapshot = json.loads(request(build + 'api/json?' + urlencode({'tree': 'number,result,building,duration,timestamp,url,artifacts[fileName,relativePath],actions[totalCount,failCount,skipCount,causes[shortDescription]]'})))
        prefix = args.prefix + '-' + args.branch + '-' + str(snapshot['number'])
        (evidence / (prefix + '.json')).write_text(json.dumps(snapshot, indent=2) + '\n', encoding='utf-8')
        (evidence / (prefix + '.txt')).write_bytes(request(build + 'consoleText'))
        (evidence / (prefix + '-stages.json')).write_bytes(request(build + 'wfapi/describe'))
        for artifact in snapshot.get('artifacts', []):
            if artifact['fileName'].endswith('-timing.json') or artifact['relativePath'] in ('dist/build.json', 'dist/push.json'):
                target = evidence / (prefix + '-' + artifact['fileName'])
                target.write_bytes(request(build + 'artifact/' + quote(artifact['relativePath'], safe='/')))
        print('Evidências locais guardadas: ' + prefix)
except HTTPError as error:
    message = error.read().decode(errors='replace')
    print(f'Jenkins respondeu HTTP {error.code}: ' + message[:1800])
    raise SystemExit(1)
