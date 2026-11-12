"""Liga o Jenkins local à branch ca5-part2 do GitHub, com credencial por projeto.

Usa a sessão Docker Desktop já autenticada; não imprime nem grava o token.
A configuração não altera branches Git nem envia a chave SSH ao GitHub.
"""
import base64
import http.cookiejar
import json
from pathlib import Path
import subprocess
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import HTTPCookieProcessor, Request, build_opener

part = Path(__file__).resolve().parents[1]
password = (part / '.local/secrets/admin_password').read_text(encoding='utf-8').strip()
docker_config = json.loads((Path.home() / '.docker/config.json').read_text(encoding='utf-8'))
helper = docker_config.get('credHelpers', {}).get('https://index.docker.io/v1/', docker_config.get('credsStore'))
if not helper:
    raise SystemExit('É necessário um credential helper Docker já autenticado.')
result = subprocess.run(['docker-credential-' + helper, 'get'], input='https://index.docker.io/v1/\n', text=True, capture_output=True)
if result.returncode:
    raise SystemExit('Não foi possível ler a credencial Docker Hub; faz login primeiro.')
credential = json.loads(result.stdout)
if credential.get('Username') != 'luizbsilv' or not credential.get('Secret'):
    raise SystemExit('A credencial Docker Hub não corresponde ao utilizador esperado.')
authorization = 'Basic ' + base64.b64encode(('luiz:' + password).encode()).decode()
opener = build_opener(HTTPCookieProcessor(http.cookiejar.CookieJar()))
base = 'http://127.0.0.1:18080/'

def request(path, data=None):
    headers = {'Authorization': authorization}
    if data is not None:
        crumb = json.loads(request('crumbIssuer/api/json'))
        headers[crumb['crumbRequestField']] = crumb['crumb']
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    return opener.open(Request(base + path, data=data, headers=headers), timeout=45).read()

payload = json.dumps({'username': credential['Username'], 'token': credential['Secret']})
script = '''
import groovy.json.JsonSlurper
import jenkins.model.Jenkins
import jenkins.plugins.git.GitSCMSource
import jenkins.plugins.git.traits.BranchDiscoveryTrait
import jenkins.scm.impl.trait.RegexSCMHeadFilterTrait
import jenkins.branch.BranchSource
import org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject
import org.jenkinsci.plugins.workflow.multibranch.WorkflowBranchProjectFactory
import com.cloudbees.hudson.plugins.folder.properties.FolderCredentialsProvider.FolderCredentialsProperty
import com.cloudbees.plugins.credentials.CredentialsProvider
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl

def instance = Jenkins.get()
def project = instance.getItem('ca5-github')
if (!project) project = instance.createProject(WorkflowMultiBranchProject.class, 'ca5-github')
assert project instanceof WorkflowMultiBranchProject
def payload = new JsonSlurper().parseText(PAYLOAD)
def credential = new UsernamePasswordCredentialsImpl(CredentialsScope.GLOBAL,
    'dockerhub-ca5', 'Docker Hub: âmbito exclusivo ca5-github', payload.username, payload.token)
if (!project.getProperties().get(FolderCredentialsProperty.class)) {
    project.addProperty(new FolderCredentialsProperty([]))
}
def store = CredentialsProvider.lookupStores(project).find { it.context == project }
assert store != null
def previous = store.getCredentials(Domain.global()).find { it.id == credential.id }
if (previous) store.updateCredentials(Domain.global(), previous, credential)
else store.addCredentials(Domain.global(), credential)
def source = new GitSCMSource('https://github.com/JP-142004/cogsi2627-1260168-1260204.git')
source.setId('ca5-github-scm')
source.setTraits([new BranchDiscoveryTrait(), new RegexSCMHeadFilterTrait('ca5-part2')])
project.getSourcesList().clear()
project.getSourcesList().add(new BranchSource(source))
def factory = new WorkflowBranchProjectFactory()
factory.setScriptPath('CA5/Part2/Jenkinsfile')
project.setProjectFactory(factory)
project.save()
project.scheduleBuild2(0)
println('CA5_GITHUB_CONFIGURED')
'''.replace('PAYLOAD', json.dumps(payload))
try:
    response = request('scriptText', urlencode({'script': script}).encode()).decode()
except HTTPError as error:
    raise SystemExit(f'Jenkins respondeu HTTP {error.code}; detalhes omitidos para proteger a credencial.') from None
if 'CA5_GITHUB_CONFIGURED' not in response:
    raise SystemExit('Jenkins não confirmou a configuração; resposta omitida para proteger a credencial.')
print('Projeto ca5-github configurado e indexação pedida; filtro exclusivo ca5-part2.')
print('Docker Hub configurado apenas neste projeto; a credencial do registo local foi preservada.')
