"""Notificação SMTP da alternativa, sem imprimir nem arquivar credenciais."""
from email.message import EmailMessage
import json
import os
import smtplib
import ssl

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
connection = smtplib.SMTP_SSL(host, port, timeout=30, context=ssl.create_default_context()) if use_ssl else smtplib.SMTP(host, port, timeout=30)
with connection as smtp:
    if use_starttls and not use_ssl:
        smtp.starttls(context=ssl.create_default_context())
    username = os.environ.get('SMTP_USERNAME', '')
    password = os.environ.get('SMTP_PASSWORD', '')
    if username or password:
        if not username or not password:
            raise SystemExit('Fornece os dois campos de autenticação SMTP.')
        smtp.login(username, password)
    smtp.send_message(message)
print(f'Notificação SMTP enviada: {status}.')
