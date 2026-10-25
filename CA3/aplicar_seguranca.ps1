# aplicar_seguranca.ps1
# Cria/atualiza os ficheiros da parte de seguranca do CA3 (Ansible).
# Executar a partir da pasta CA3 do repositorio:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\aplicar_seguranca.ps1

$ErrorActionPreference = 'Stop'
$root = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'ansible'
$utf8 = New-Object System.Text.UTF8Encoding $false

function Write-AnsibleFile {
    param([string]$Relative, [string]$Content)
    $path = Join-Path $root $Relative
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $text = $Content.Replace("`r`n", "`n").TrimEnd("`n") + "`n"
    [System.IO.File]::WriteAllText($path, $text, $utf8)
    Write-Host "Escrito: ansible/$Relative"
}

Write-AnsibleFile '.ansible-lint' @'
# Regras tratadas como aviso, nao como erro.
# no-handler: a tarefa de compilacao Gradle (role bookstore, herdada do Luiz) deve
# correr quando o codigo muda; nao reinicia nada por si propria.
warn_list:
  - no-handler
'@

Write-AnsibleFile 'site.yml' @'
---
- name: Aplicar politica de seguranca (grupo, utilizador, PAM)
  hosts: database:application
  become: true

  roles:
    - security

- name: Configurar o servidor de base de dados
  hosts: database
  become: true

  roles:
    - h2

- name: Configurar a aplicacao Bookstore
  hosts: application
  become: true

  roles:
    - bookstore

- name: Configurar o reverse proxy
  hosts: reverse_proxy
  become: true

  roles:
    - nginx
'@

Write-AnsibleFile 'roles/security/defaults/main.yml' @'
---
developers_group: developers
dev_user: devuser

# Hash SHA-512 gerado com: mkpasswd --method=sha-512
# Por omissao a conta fica sem password (bloqueada). Para testar a politica:
#   ansible-playbook ... -e dev_user_password_hash='<hash>'
dev_user_password_hash: "!"

# Politica de passwords (pam_pwquality / pam_pwhistory)
pwquality_minlen: 12
pwquality_minclass: 3
pwhistory_remember: 5

# Bloqueio de conta (pam_faillock)
faillock_deny: 5
faillock_unlock_time: 600
faillock_fail_interval: 900
'@

Write-AnsibleFile 'roles/security/tasks/main.yml' @'
---
- name: Criar grupo e utilizador de desenvolvimento
  ansible.builtin.import_tasks: accounts.yml

- name: Aplicar politica de passwords e bloqueio
  ansible.builtin.import_tasks: password_policy.yml

- name: Aplicar configuracao PAM
  ansible.builtin.import_tasks: pam.yml
'@

Write-AnsibleFile 'roles/security/tasks/accounts.yml' @'
---
- name: Criar grupo developers
  ansible.builtin.group:
    name: "{{ developers_group }}"
    state: present

- name: Criar utilizador devuser no grupo developers
  ansible.builtin.user:
    name: "{{ dev_user }}"
    shell: /bin/bash
    create_home: true
    groups: "{{ developers_group }}"
    append: true
    password: "{{ dev_user_password_hash }}"
    update_password: on_create
    state: present
  no_log: true
'@

Write-AnsibleFile 'roles/security/tasks/password_policy.yml' @'
---
- name: Instalar modulos PAM de complexidade e bloqueio
  ansible.builtin.apt:
    name:
      - libpam-pwquality
      - libpam-modules
    state: present
    update_cache: true
    cache_valid_time: 3600
  register: pam_packages
  retries: 3
  delay: 5
  until: pam_packages is succeeded

- name: Definir requisitos de complexidade (pwquality)
  ansible.builtin.lineinfile:
    path: /etc/security/pwquality.conf
    regexp: "^#?\\s*{{ item.key }}\\s*="
    line: "{{ item.key }} = {{ item.value }}"
    create: true
    owner: root
    group: root
    mode: '0644'
  loop:
    - {key: minlen, value: "{{ pwquality_minlen }}"}
    - {key: minclass, value: "{{ pwquality_minclass }}"}

- name: Definir politica de bloqueio (faillock)
  ansible.builtin.copy:
    dest: /etc/security/faillock.conf
    owner: root
    group: root
    mode: '0644'
    backup: true
    content: |
      # Gerido pelo Ansible (role security)
      deny = {{ faillock_deny }}
      unlock_time = {{ faillock_unlock_time }}
      fail_interval = {{ faillock_fail_interval }}
'@

Write-AnsibleFile 'roles/security/tasks/pam.yml' @'
---
- name: Copiar common-auth (bloqueio apos falhas)
  ansible.builtin.copy:
    src: common-auth
    dest: /etc/pam.d/common-auth
    owner: root
    group: root
    mode: '0644'
    backup: true

- name: Copiar common-account (conta bloqueada)
  ansible.builtin.copy:
    src: common-account
    dest: /etc/pam.d/common-account
    owner: root
    group: root
    mode: '0644'
    backup: true

- name: Copiar common-password (historico e complexidade)
  ansible.builtin.copy:
    src: common-password
    dest: /etc/pam.d/common-password
    owner: root
    group: root
    mode: '0644'
    backup: true
'@

Write-AnsibleFile 'roles/security/files/common-auth' @'
# Gerido pelo Ansible (role security). Base: Ubuntu 22.04 + pam_faillock.
auth	required			pam_faillock.so preauth
auth	[success=1 default=ignore]	pam_unix.so nullok
auth	[default=die]			pam_faillock.so authfail
auth	sufficient			pam_faillock.so authsucc
auth	requisite			pam_deny.so
auth	required			pam_permit.so
auth	optional			pam_cap.so
'@

Write-AnsibleFile 'roles/security/files/common-account' @'
# Gerido pelo Ansible (role security). Base: Ubuntu 22.04 + pam_faillock.
account	required			pam_faillock.so
account	[success=1 new_authtok_reqd=done default=ignore]	pam_unix.so
account	requisite			pam_deny.so
account	required			pam_permit.so
'@

Write-AnsibleFile 'roles/security/files/common-password' @'
# Gerido pelo Ansible (role security). Base: Ubuntu 22.04 + pam_pwhistory.
password	requisite			pam_pwquality.so retry=3
password	required			pam_pwhistory.so remember=5 use_authtok enforce_for_root
password	[success=1 default=ignore]	pam_unix.so obscure use_authtok try_first_pass yescrypt
password	requisite			pam_deny.so
password	required			pam_permit.so
'@

Write-AnsibleFile 'roles/h2/tasks/main.yml' @'
---
- name: Atualizar a cache de pacotes
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600
  retries: 3
  delay: 5
  register: apt_update
  until: apt_update is succeeded

- name: Instalar Java para executar H2
  ansible.builtin.apt:
    name: openjdk-17-jre-headless
    state: present
  retries: 3
  delay: 5
  register: java_install
  until: java_install is succeeded

- name: Criar grupo de servico H2
  ansible.builtin.group:
    name: h2
    system: true
    state: present

- name: Criar utilizador de servico H2
  ansible.builtin.user:
    name: h2
    group: h2
    groups: developers
    append: true
    system: true
    shell: /usr/sbin/nologin
    create_home: false
    state: present

- name: Criar diretorio do programa H2
  ansible.builtin.file:
    path: /opt/h2
    state: directory
    owner: root
    group: h2
    mode: '0750'

- name: Criar diretorio dos dados H2 (restrito ao grupo developers, setgid)
  ansible.builtin.file:
    path: /var/lib/h2
    state: directory
    owner: h2
    group: developers
    mode: 'u=rwX,g=rwXs,o='

- name: Criar pasta de drop-ins do servico H2
  ansible.builtin.file:
    path: /etc/systemd/system/h2-server.service.d
    state: directory
    owner: root
    group: root
    mode: '0755'

- name: Definir umask do servico H2 (ficheiros da BD com grupo developers)
  ansible.builtin.copy:
    dest: /etc/systemd/system/h2-server.service.d/umask.conf
    owner: root
    group: root
    mode: '0644'
    content: |
      [Service]
      UMask=0007
  notify: Reiniciar H2

- name: Descarregar H2
  ansible.builtin.get_url:
    url: https://repo.maven.apache.org/maven2/com/h2database/h2/2.2.224/h2-2.2.224.jar
    dest: /opt/h2/h2-2.2.224.jar
    owner: root
    group: h2
    mode: '0640'
  register: h2_download
  retries: 3
  delay: 5
  until: h2_download is succeeded

- name: Instalar definicao do servico H2
  ansible.builtin.copy:
    src: h2-server.service
    dest: /etc/systemd/system/h2-server.service
    owner: root
    group: root
    mode: '0644'
  notify: Reiniciar H2

- name: Aplicar alteracoes pendentes do servico
  ansible.builtin.meta: flush_handlers

- name: Garantir H2 iniciado e ativo no arranque
  ansible.builtin.systemd:
    name: h2-server
    enabled: true
    state: started

- name: Aguardar pela porta TCP do H2
  ansible.builtin.wait_for:
    host: 127.0.0.1
    port: 9092
    timeout: 60

- name: Verificar resposta SQL do H2
  ansible.builtin.command:
    argv:
      - /usr/bin/java
      - -cp
      - /opt/h2/h2-2.2.224.jar
      - org.h2.tools.Shell
      - -url
      - jdbc:h2:tcp://127.0.0.1:9092/mem:ca3_healthcheck
      - -user
      - sa
      - -password
      - ""
      - -sql
      - "SELECT 'CA3_H2_OK' AS STATUS;"
  register: h2_health
  changed_when: false
  failed_when: >
    h2_health.rc != 0 or
    'CA3_H2_OK' not in h2_health.stdout
  retries: 5
  delay: 3
  until: h2_health is succeeded
  no_log: true
'@

Write-AnsibleFile 'roles/bookstore/tasks/main.yml' @'
---
- name: Atualizar a cache de pacotes
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600
  register: app_apt_update
  retries: 3
  delay: 5
  until: app_apt_update is succeeded

- name: Instalar ferramentas para compilar Bookstore
  ansible.builtin.apt:
    name:
      - openjdk-17-jdk
      - unzip
    state: present
  register: app_packages
  retries: 3
  delay: 5
  until: app_packages is succeeded

- name: Criar pastas para compilar Bookstore
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: vagrant
    group: vagrant
    mode: '0750'
  loop:
    - /home/vagrant/bookstore-build
    - /home/vagrant/bookstore-build/app

- name: Copiar codigo e configuracao Gradle
  ansible.builtin.copy:
    src: "/mnt/bookstore-source/{{ item }}"
    dest: "/home/vagrant/bookstore-build/{{ item }}"
    remote_src: true
    owner: vagrant
    group: vagrant
    mode: 'u=rwX,g=rX,o='
    directory_mode: '0750'
  register: bookstore_source
  loop:
    - settings.gradle
    - gradlew
    - gradle/
    - app/build.gradle
    - app/src/

- name: Verificar se o JAR Bookstore ja existe
  ansible.builtin.stat:
    path: /home/vagrant/bookstore-build/app/build/libs/app-1.0.0.jar
  register: bookstore_jar

- name: Compilar Bookstore com Gradle
  become: true
  become_user: vagrant
  ansible.builtin.command:
    argv:
      - /bin/bash
      - ./gradlew
      - :app:bootJar
      - --no-daemon
    chdir: /home/vagrant/bookstore-build
  when: bookstore_source.changed or not bookstore_jar.stat.exists

- name: Criar grupo de servico Bookstore
  ansible.builtin.group:
    name: bookstore
    system: true
    state: present

- name: Criar utilizador de servico Bookstore
  ansible.builtin.user:
    name: bookstore
    group: bookstore
    groups: developers
    append: true
    system: true
    shell: /usr/sbin/nologin
    create_home: false
    state: present

- name: Criar pastas da aplicacao e configuracao (restritas ao grupo developers)
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: developers
    mode: '0750'
  loop:
    - /opt/bookstore
    - /etc/bookstore

- name: Instalar JAR da Bookstore
  ansible.builtin.copy:
    src: /home/vagrant/bookstore-build/app/build/libs/app-1.0.0.jar
    dest: /opt/bookstore/bookstore.jar
    remote_src: true
    owner: root
    group: developers
    mode: '0640'
  notify: Reiniciar Bookstore

- name: Instalar configuracao da Bookstore
  ansible.builtin.copy:
    src: application.properties
    dest: /etc/bookstore/application.properties
    owner: root
    group: developers
    mode: '0640'
  no_log: true
  notify: Reiniciar Bookstore

- name: Verificar acesso da app ao servidor H2
  ansible.builtin.wait_for:
    host: 192.168.56.30
    port: 9092
    timeout: 60

- name: Instalar definicao do servico Bookstore
  ansible.builtin.copy:
    src: bookstore.service
    dest: /etc/systemd/system/bookstore.service
    owner: root
    group: root
    mode: '0644'
  notify: Reiniciar Bookstore

- name: Aplicar alteracoes pendentes da Bookstore
  ansible.builtin.meta: flush_handlers

- name: Garantir Bookstore iniciada e ativa no arranque
  ansible.builtin.systemd:
    name: bookstore
    enabled: true
    state: started

- name: Verificar consulta de livros pela aplicacao
  ansible.builtin.uri:
    url: http://127.0.0.1:8080/books
    status_code: 200
    return_content: true
  register: bookstore_health
  retries: 20
  delay: 3
  until: bookstore_health.status | default(0) == 200
'@

Write-Host ""
Write-Host "Ficheiros escritos. Proximo passo: .\prepare.ps1 (copia ansible/ para a VM app)."
