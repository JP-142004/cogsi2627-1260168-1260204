FROM eclipse-temurin:17-jdk-jammy AS java17
FROM docker:29.9.2-cli AS dockercli

# Versão verificada no início do laboratório: Jenkins LTS 2.580.2, Java 21.
FROM jenkins/jenkins:lts-jdk21@sha256:74401de6a6f92e1afe1b02d1c8e3d0c33f263bfb5275dd8813f9150355f2367b

USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       python3 python3-venv openssh-client curl apache2-utils \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/ansible \
    && /opt/ansible/bin/pip install --no-cache-dir ansible-core==2.19.4

COPY --from=java17 /opt/java/openjdk /opt/java17
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx

ENV JAVA17_HOME=/opt/java17
ENV PATH=/opt/ansible/bin:${PATH}
COPY ansible/requirements.yml /tmp/ansible-requirements.yml
RUN ansible-galaxy collection install -r /tmp/ansible-requirements.yml -p /opt/ansible/collections
ENV ANSIBLE_COLLECTIONS_PATH=/opt/ansible/collections

COPY jenkins/plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
COPY jenkins/init.groovy.d/ /usr/share/jenkins/ref/init.groovy.d/

USER jenkins
