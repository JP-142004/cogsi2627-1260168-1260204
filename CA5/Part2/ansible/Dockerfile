# Controlador Ansible para os testes locais, sem instalar Ansible no Windows.
FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir --disable-pip-version-check ansible-core==2.17.14

COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml

WORKDIR /work
ENTRYPOINT ["ansible-playbook"]
