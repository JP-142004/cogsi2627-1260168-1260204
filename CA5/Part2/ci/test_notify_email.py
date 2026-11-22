"""Testes do envio: estados, TLS, OAuth e ausência de credenciais nos erros."""
from contextlib import redirect_stdout
from io import StringIO
import json
import os
from pathlib import Path
import runpy
import unittest
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError


class NotificationTests(unittest.TestCase):
    def execute(self, extra=None, token_error=None):
        environment = {
            'NEEDS_JSON': json.dumps({'tests': {'result': 'success'}, 'image': {'result': 'success', 'outputs': {'image': 'example/app:1'}}}),
            'SMTP_HOST': 'mailpit', 'SMTP_PORT': '1025', 'SMTP_STARTTLS': 'false',
            'NOTIFY_FROM': 'ci@example.test', 'NOTIFY_TO': 'recipient@example.test',
            'GITHUB_RUN_NUMBER': '1', 'GITHUB_RUN_ID': '2', 'GITHUB_SERVER_URL': 'https://github.com',
            'GITHUB_REPOSITORY': 'example/repo', 'GITHUB_REF': 'refs/heads/ca5-part2', 'GITHUB_SHA': 'abc',
        }
        environment.update(extra or {})
        smtp = MagicMock()
        smtp.__enter__.return_value = smtp
        response = MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps({'access_token': 'dummy-access-token'})
        with patch.dict(os.environ, environment, clear=True), patch('smtplib.SMTP', return_value=smtp) as factory, \
                patch('urllib.request.urlopen', return_value=response, side_effect=token_error) as oauth, redirect_stdout(StringIO()) as output:
            runpy.run_path(str(Path(__file__).with_name('notify-email.py')), run_name='__main__')
        return smtp, factory, oauth, output.getvalue()

    def test_local_success(self):
        smtp, _, _, output = self.execute()
        message = smtp.send_message.call_args.args[0]
        self.assertIn('SUCCESS', message['Subject'])
        self.assertIn('example/app:1', message.get_content())
        self.assertIn('SUCCESS', output)
        smtp.login.assert_not_called()

    def test_skipped_image_is_not_reported_as_published(self):
        needs = {'tests': {'result': 'failure'}, 'image': {'result': 'skipped', 'outputs': {'image': '${{ steps.identity.outputs.image }}'}}}
        smtp, _, _, _ = self.execute({'NEEDS_JSON': json.dumps(needs)})
        message = smtp.send_message.call_args.args[0]
        self.assertIn('FAILURE', message['Subject'])
        self.assertIn('não construída', message.get_content())
        self.assertNotIn('${{', message.get_content())

    def test_external_without_authentication_is_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'exige autenticação'):
            self.execute({'SMTP_HOST': 'smtp.office365.com'})

    def test_reference_is_rebuilt_from_public_repository_and_tag(self):
        smtp, _, _, _ = self.execute({'NEEDS_JSON': json.dumps({'image': {'result': 'success', 'outputs': {'tag': 'build-42'}}}),
                                     'BOOKSTORE_IMAGE_REPOSITORY': 'example/app'})
        self.assertIn('example/app:build-42', smtp.send_message.call_args.args[0].get_content())

    def test_password_without_tls_is_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'exige TLS'):
            self.execute({'SMTP_USERNAME': 'ci@example.test', 'SMTP_PASSWORD': 'dummy-password'})

    def test_oauth_uses_tls_and_xoauth2(self):
        smtp, _, oauth, output = self.execute({
            'SMTP_HOST': 'smtp.office365.com', 'SMTP_STARTTLS': 'true', 'SMTP_USERNAME': 'ci@example.test',
            'SMTP_OAUTH_TENANT_ID': 'tenant.example', 'SMTP_OAUTH_CLIENT_ID': 'dummy-client', 'SMTP_OAUTH_CLIENT_SECRET': 'dummy-secret',
        })
        self.assertTrue(oauth.call_args.args[0].full_url.startswith('https://login.microsoftonline.com/tenant.example/'))
        self.assertIn('starttls', [call[0] for call in smtp.method_calls])
        mechanism, callback = smtp.auth.call_args.args
        self.assertEqual('XOAUTH2', mechanism)
        self.assertEqual('user=ci@example.test\x01auth=Bearer dummy-access-token\x01\x01', callback())
        self.assertEqual('', callback(b'error-challenge'))
        self.assertNotIn('dummy-access-token', output)
        self.assertNotIn('dummy-secret', output)

    def test_oauth_failure_does_not_expose_response(self):
        with self.assertRaises(SystemExit) as result:
            self.execute({'SMTP_STARTTLS': 'true', 'SMTP_USERNAME': 'ci@example.test', 'SMTP_OAUTH_TENANT_ID': 'tenant.example',
                          'SMTP_OAUTH_CLIENT_ID': 'dummy-client', 'SMTP_OAUTH_CLIENT_SECRET': 'dummy-secret'},
                         HTTPError('https://login.microsoftonline.com', 401, 'dummy-secret', {}, None))
        self.assertIn('HTTP 401', str(result.exception))
        self.assertNotIn('dummy-secret', str(result.exception))


if __name__ == '__main__':
    unittest.main()
