"""Acceptance checks from the host; uses only Python's standard library."""
import json
import socket
import subprocess
import time
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EVIDENCE = ROOT / 'evidence'


def docker(*args):
    return subprocess.check_output(['docker', *args], text=True, encoding='utf-8').strip()


def request(port, path, payload=None):
    body = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        f'http://127.0.0.1:{port}{path}', data=body,
        headers={'Content-Type': 'application/json'},
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        return json.load(response)


def chat_check(port):
    sockets = []
    streams = []
    try:
        for name in ['LuizCA4', 'ClienteCA4']:
            sock = socket.create_connection(('127.0.0.1', port), timeout=5)
            sockets.append(sock)
            stream = sock.makefile('rw', encoding='utf-8', newline='\n')
            streams.append(stream)
            assert stream.readline().strip() == 'SUBMITNAME'
            stream.write(name + '\n')
            stream.flush()
            assert stream.readline().strip() == f'NAMEACCEPTED {name}'
        assert streams[0].readline().strip() == 'MESSAGE ClienteCA4 has joined'
        for sender, name in [(0, 'LuizCA4'), (1, 'ClienteCA4')]:
            message = f'teste da versao Docker pelo cliente {sender + 1}'
            streams[sender].write(message + '\n')
            streams[sender].flush()
            for stream in streams:
                assert stream.readline().strip() == f'MESSAGE {name}: {message}'
        return 'Dois clientes no host registados; mensagens recebidas nos dois sentidos.'
    finally:
        for stream in streams:
            stream.close()
        for sock in sockets:
            sock.close()


def bookstore_check(port):
    assert request(port, '/actuator/health')['status'] == 'UP'
    books = request(port, '/books')
    assert isinstance(books, list)
    created = request(port, '/books', {'title': 'Teste CA4', 'author': 'Grupo COGSI', 'price': 12.5})
    assert created['id'] is not None
    book = request(port, f"/books/{created['id']}")
    assert book['title'] == 'Teste CA4'
    return f"Health UP; listagem, criação e leitura do livro {created['id']} pelo host."


def main():
    EVIDENCE.mkdir(exist_ok=True)
    results = []
    for app, internal_port in [('chat', 59001), ('bookstore', 8080)]:
        for version in range(1, 4):
            image = f'ca4-{app}:v{version}'
            name = f'ca4-check-{app}-v{version}-{uuid.uuid4().hex[:8]}'
            docker('run', '-d', '--name', name, '-p', f'127.0.0.1::{internal_port}', image)
            try:
                info = json.loads(docker('inspect', name))[0]
                port = int(info['NetworkSettings']['Ports'][f'{internal_port}/tcp'][0]['HostPort'])
                deadline = time.monotonic() + 120
                while True:
                    try:
                        if app == 'bookstore':
                            assert request(port, '/actuator/health')['status'] == 'UP'
                        else:
                            with socket.create_connection(('127.0.0.1', port), timeout=2):
                                pass
                        break
                    except (OSError, AssertionError):
                        if time.monotonic() >= deadline:
                            raise TimeoutError(f'{image} não arrancou')
                        time.sleep(1)
                detail = chat_check(port) if app == 'chat' else bookstore_check(port)
                uid = docker('exec', name, 'id', '-u')
                javac = docker('exec', name, 'sh', '-c', 'command -v javac || true')
                git = docker('exec', name, 'sh', '-c', 'command -v git || true')
                if version == 3:
                    assert uid != '0', 'A versão 3 deve executar sem root'
                if version != 1:
                    assert not javac and not git, 'A imagem final deve conter apenas o runtime'
                stats = json.loads(docker('stats', '--no-stream', '--format', '{{json .}}', name))
                image_id = docker('image', 'inspect', '--format', '{{.Id}}', image)
                results.append(dict(image=image, imageId=image_id,
                                    measuredAt=datetime.now(timezone.utc).isoformat(),
                                    result='PASS', detail=detail, hostPort=port,
                                    uid=uid, javac=javac, git=git, stats=stats))
                print(f'{image}: PASS — {detail}', flush=True)
                (EVIDENCE / 'verification.json').write_text(
                    json.dumps(results, ensure_ascii=False, indent=2), encoding='utf-8')
            finally:
                (EVIDENCE / f'{app}-v{version}-runtime.txt').write_text(
                    docker('logs', name), encoding='utf-8')
                docker('rm', '-f', name)


if __name__ == '__main__':
    main()
