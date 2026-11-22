"""Configura Gmail por referência a uma credencial já criada no Jenkins.

Não lê nem exporta a palavra-passe SMTP. O Mailpit mantém-se como conta
predefinida; a conta adicional Gmail é escolhida pelo remetente do pipeline.
"""
import argparse
import base64
import http.cookiejar
import json
from pathlib import Path
import re
import sys
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import HTTPCookieProcessor, Request, build_opener

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
parser = argparse.ArgumentParser()
parser.add_argument('--sender', required=True)
parser.add_argument('--recipient', required=True)
parser.add_argument('--credential-id', default='ca5-gmail-smtp')
parser.add_argument('--check', action='store_true', help='Só verificar a existência e os metadados da credencial')
parser.add_argument('--send-test', action='store_true', help='Enviar um aviso isolado, sem checkout, imagem ou deploy')
args = parser.parse_args()
if args.check and args.send_test:
    parser.error('--check e --send-test não podem ser combinados.')
for address in (args.sender, args.recipient):
    if not re.fullmatch(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', address):
        parser.error('Indica endereços simples, sem nomes de apresentação.')
part = Path(__file__).resolve().parents[1]
admin_password = (part / '.local/secrets/admin_password').read_text(encoding='utf-8').strip()
authorization = 'Basic ' + base64.b64encode(('luiz:' + admin_password).encode()).decode()
opener = build_opener(HTTPCookieProcessor(http.cookiejar.CookieJar()))
base = 'http://127.0.0.1:18080/'

def request(path, data=None):
    headers = {'Authorization': authorization}
    if data is not None:
        crumb = json.loads(request('crumbIssuer/api/json'))
        headers[crumb['crumbRequestField']] = crumb['crumb']
        headers['Content-Type'] = 'application/x-www-form-urlencoded'
    return opener.open(Request(base + path, data=data, headers=headers), timeout=45).read()

payload = base64.b64encode(json.dumps({
    'sender': args.sender, 'recipient': args.recipient, 'credentialId': args.credential_id,
    'checkOnly': args.check, 'sendTest': args.send_test,
}).encode()).decode()
script = '''
import groovy.json.JsonOutput
import groovy.json.JsonSlurper
import jenkins.model.Jenkins
import hudson.plugins.emailext.ExtendedEmailPublisherDescriptor
import hudson.plugins.emailext.MailAccount
import hudson.slaves.EnvironmentVariablesNodeProperty
import hudson.model.ParametersDefinitionProperty
import hudson.model.StringParameterDefinition
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.common.StandardUsernamePasswordCredentials
import com.cloudbees.plugins.credentials.domains.Domain
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition

def payload = new JsonSlurper().parseText(new String('PAYLOAD'.decodeBase64(), 'UTF-8'))
def instance = Jenkins.get()
def credential = SystemCredentialsProvider.getInstance().getStore()
    .getCredentials(Domain.global()).find { it.id == payload.credentialId }
def validType = credential instanceof StandardUsernamePasswordCredentials
def usernameMatches = validType && credential.username == payload.sender
def report = [credential_found: credential != null, credential_type_valid: validType,
              username_matches_sender: usernameMatches, smtp_password_read_or_exported_by_helper: false]
if (payload.checkOnly || !usernameMatches) {
    println(JsonOutput.toJson(report))
    return
}

def email = instance.getDescriptorByType(ExtendedEmailPublisherDescriptor.class)
def gmail = new MailAccount()
gmail.setAddress(payload.sender)
gmail.setSmtpHost('smtp.gmail.com')
gmail.setSmtpPort('587')
gmail.setCredentialsId(payload.credentialId)
gmail.setUseTls(true)
gmail.setUseSsl(false)
def accounts = new ArrayList(email.getAddAccounts() ?: [])
accounts.removeAll { it.address?.equalsIgnoreCase(payload.sender) }
accounts.add(gmail)
email.setAddAccounts(accounts)
email.setDebugMode(false)
email.setCharset('UTF-8')
email.save()

def environment = instance.globalNodeProperties.get(EnvironmentVariablesNodeProperty.class)
if (environment == null) {
    environment = new EnvironmentVariablesNodeProperty([
        new EnvironmentVariablesNodeProperty.Entry('CA5_GMAIL_FROM', payload.sender),
        new EnvironmentVariablesNodeProperty.Entry('CA5_GMAIL_TO', payload.recipient)
    ])
    instance.globalNodeProperties.add(environment)
} else {
    environment.envVars.put('CA5_GMAIL_FROM', payload.sender)
    environment.envVars.put('CA5_GMAIL_TO', payload.recipient)
}

// Elimina o destinatário local anteriormente usado como valor por omissão
// apenas nos subjobs do projeto externo. Os parâmetros explícitos continuam disponíveis.
def external = instance.getItem('ca5-github')
external?.items?.each { job ->
    def parameters = job.getProperty(ParametersDefinitionProperty.class)
    if (parameters != null) {
        def definitions = parameters.parameterDefinitions.collect { parameter ->
            parameter.name == 'EMAIL_RECIPIENT'
                ? new StringParameterDefinition('EMAIL_RECIPIENT', '', 'Vazio usa o destinatário configurado no Jenkins')
                : parameter
        }
        job.removeProperty(ParametersDefinitionProperty.class)
        job.addProperty(new ParametersDefinitionProperty(definitions))
        job.save()
    }
}
instance.save()
report.putAll([configured: true, smtp_host: gmail.smtpHost, smtp_port: gmail.smtpPort,
    starttls: gmail.useTls, ssl: gmail.useSsl, credential_id: payload.credentialId,
    default_smtp_host: email.mailAccount.smtpHost,
    lab_mailpit_preserved: email.mailAccount.smtpHost == 'mailpit',
    environment_variable_names: ['CA5_GMAIL_FROM', 'CA5_GMAIL_TO']])

if (payload.sendTest) {
    def name = 'ca5-email-check'
    def description = 'CA5: teste SMTP isolado, sem checkout, imagem ou deploy.'
    def job = instance.getItem(name)
    if (job == null) {
        job = instance.createProject(WorkflowJob.class, name)
        job.setDescription(description)
    } else {
        assert job instanceof WorkflowJob && job.description == description : 'O nome do job de teste já está em uso.'
    }
    def flow = """pipeline {
    agent { label 'ca5-linux' }
    options { timeout(time: 3, unit: 'MINUTES'); disableConcurrentBuilds() }
    stages {
        stage('Testar Gmail') {
            steps {
                emailext(from: FROM_ADDRESS, to: TO_ADDRESS,
                    subject: 'CA5 TESTE: Jenkins Gmail',
                    body: 'Teste do envio Gmail pelo Jenkins CA5. Esta execucao nao faz checkout, build de imagem ou deploy.',
                    mimeType: 'text/plain')
            }
        }
    }
}
""".replace('FROM_ADDRESS', JsonOutput.toJson(payload.sender))
   .replace('TO_ADDRESS', JsonOutput.toJson(payload.recipient))
    job.setDefinition(new CpsFlowDefinition(flow, true))
    job.save()
    job.scheduleBuild2(0)
    report.test_job = name
    report.test_queued = true
}
println(JsonOutput.toJson(report))
'''.replace('PAYLOAD', payload)
try:
    response = request('scriptText', urlencode({'script': script}).encode()).decode()
except HTTPError as error:
    raise SystemExit(f'Jenkins respondeu HTTP {error.code}; resposta omitida para proteger a configuração local.') from None
try:
    report = json.loads(response)
except ValueError:
    raise SystemExit('O Jenkins não confirmou a configuração; resposta omitida. Nenhuma palavra-passe SMTP foi pedida ao servidor.') from None
print(json.dumps(report, ensure_ascii=False, indent=2))
if not report.get('username_matches_sender'):
    raise SystemExit('Verifica o ID, o tipo e o username da credencial no formulário do Jenkins.')
