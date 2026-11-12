"""Notificação SMTP da alternativa, sem imprimir nem arquivar credenciais."""
from email.message import EmailMessage
import json
import os
import re
import smtplib
import ssl
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

dependencies = json.loads(os.environ['NEEDS_JSON'])
results = [job['result'] for job in dependencies.values()]
status = 'FAILURE' if 'failure' in results else 'CANCELLED' if 'cancelled' in results else 'SUCCESS'
host = os.environ.get('SMTP_HOST', '').strip()
recipient = os.environ.get('NOTIFY_TO', '').strip()
sender = os.environ.get('NOTIFY_FROM', '').strip()
if not host or not recipient or not sender:
    raise SystemExit('Configura SMTP_HOST, NOTIFY_TO e NOTIFY_FROM antes de executar a alternativa.')
image_job = dependencies.get('image', {})
image = (image_job.get('outputs', {}).get('image') or 'não construída') if image_job.get('result') == 'success' else 'não construída'
message = EmailMessage()
message['From'] = sender
message['To'] = recipient
message['Subject'] = f"CA5 {status}: GitHub Actions #{os.environ['GITHUB_RUN_NUMBER']}"
url = f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
if os.environ.get('ACT') == 'true':
    url = 'Emulação local com act; consultar as evidências locais.'
message.set_content(f"Resultado: {status}\nBranch: {os.environ['GITHUB_REF']}\nCommit: {os.environ['GITHUB_SHA']}\nImagem: {image}\nExecução: {url}\n")
port = int(os.environ.get('SMTP_PORT', '587'))
use_ssl = os.environ.get('SMTP_SSL', 'false').lower() == 'true'
use_starttls = os.environ.get('SMTP_STARTTLS', 'true').lower() == 'true'
username = os.environ.get('SMTP_USERNAME', '')
password = os.environ.get('SMTP_PASSWORD', '')
tenant = os.environ.get('SMTP_OAUTH_TENANT_ID', '')
client_id = os.environ.get('SMTP_OAUTH_CLIENT_ID', '')
client_secret = os.environ.get('SMTP_OAUTH_CLIENT_SECRET', '')
access_token = None
if any((tenant, client_id, client_secret)):
    if not all((tenant, client_id, client_secret, username)):
        raise SystemExit('Configura os três campos SMTP_OAUTH e SMTP_USERNAME para autenticação Microsoft OAuth.')
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9.-]{0,253}', tenant):
        raise SystemExit('SMTP_OAUTH_TENANT_ID inválido.')
    if not (use_ssl or use_starttls):
        raise SystemExit('OAuth SMTP exige TLS.')
    payload = urlencode({'client_id': client_id, 'client_secret': client_secret,
                         'scope': 'https://outlook.office365.com/.default', 'grant_type': 'client_credentials'}).encode()
    try:
        with urlopen(Request(f'https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token', data=payload,
                             headers={'Content-Type': 'application/x-www-form-urlencoded'}), timeout=30) as response:
            access_token = json.load(response).get('access_token')
    except HTTPError as error:
        raise SystemExit(f'Autorização Microsoft OAuth recusada (HTTP {error.code}); verifica a aplicação e o consentimento do administrador.') from None
    if not access_token:
        raise SystemExit('A autorização Microsoft não devolveu um access token.')
elif username or password:
    if not username or not password:
        raise SystemExit('Falta a credencial de envio SMTP. Configura OAuth para Microsoft 365 ou uma credencial SMTP autorizada nos Secrets.')
elif host not in ('localhost', '127.0.0.1', 'host.docker.internal', 'mailpit'):
    raise SystemExit('O envio externo exige autenticação SMTP. As credenciais ainda não estão configuradas.')
if (access_token or password) and not (use_ssl or use_starttls):
    raise SystemExit('A autenticação SMTP externa exige TLS.')
connection = smtplib.SMTP_SSL(host, port, timeout=30, context=ssl.create_default_context()) if use_ssl else smtplib.SMTP(host, port, timeout=30)
with connection as smtp:
    if use_starttls and not use_ssl:
        smtp.starttls(context=ssl.create_default_context())
    if access_token:
        auth = f'user={username}\x01auth=Bearer {access_token}\x01\x01'
        smtp.auth('XOAUTH2', lambda challenge=None: auth if challenge is None else '')
    elif password:
        smtp.login(username, password)
    smtp.send_message(message)
print(f'Notificação SMTP enviada: {status}.')
