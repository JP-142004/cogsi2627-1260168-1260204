# CA3 - Provisionamento com Ansible: Parte de Segurança

Esta secção documenta a parte de segurança do CA3, desenvolvida sobre a infraestrutura Ansible do Luiz (H2, Bookstore e Nginx). O objetivo é reproduzir o trabalho passo a passo: criar o grupo e o utilizador de desenvolvimento, restringir o acesso aos dados, aplicar uma política de passwords e de bloqueio com PAM, e validar tudo com execuções idempotentes.

## 1. Requisitos cobertos

| Requisito | Onde | Estado |
|-----------|------|--------|
| Grupo `developers` e utilizador `devuser` em `app` e `db` | `roles/security/tasks/accounts.yml` | Feito |
| `devuser` pertence a `developers` | `accounts.yml` | Feito |
| Aplicação e base de dados em diretórios restritos a `developers` | `roles/bookstore`, `roles/h2` | Feito |
| Contas de serviço `bookstore` e `h2` com acesso necessário | `roles/bookstore`, `roles/h2` (grupo suplementar) | Feito |
| Mínimo de 12 caracteres | `pwquality.conf` (`minlen = 12`) | Configurado, não testado com password |
| Pelo menos 3 de 4 classes de caracteres | `pwquality.conf` (`minclass = 3`) | Configurado, não testado com password |
| Histórico de 5 passwords | `pam_pwhistory` (`remember=5`) | Configurado, não testado com password |
| Bloqueio de 10 minutos após 5 falhas | `pam_faillock` (`deny=5`, `unlock_time=600`) | Configurado, não testado com falhas |
| `no_log: true` em tarefas sensíveis | `accounts.yml`, `bookstore`, `h2` | Feito |
| Idempotência (segunda execução com 0 alterações) | Todo o playbook | Validado |

## 2. Pré-requisitos

- Vagrant e VirtualBox instalados no Windows.
- Repositório clonado e branch `ca3-part2` criada a partir de `main`.
- VMs `db`, `app` e `proxy` criadas pelo `prepare.ps1`.

## 3. Estrutura dos ficheiros

```text
CA3/
├── Vagrantfile
├── prepare.ps1                 # Copia ansible/ para a VM app e prepara o controlador
└── ansible/
    ├── hosts.ini               # Inventário: database, application, reverse_proxy
    ├── site.yml                # Play de segurança primeiro, depois serviços
    ├── .ansible-lint           # no-handler como aviso (justificado)
    └── roles/
        ├── security/
        │   ├── defaults/main.yml
        │   ├── tasks/
        │   │   ├── main.yml            # import_tasks dos três ficheiros abaixo
        │   │   ├── accounts.yml        # grupo developers e devuser
        │   │   ├── password_policy.yml # pwquality e faillock
        │   │   └── pam.yml             # copia common-auth, common-account, common-password
        │   └── files/
        │       ├── common-auth
        │       ├── common-account
        │       └── common-password
        ├── h2/tasks/main.yml           # alterado: grupo developers e umask
        └── bookstore/tasks/main.yml    # alterado: grupo developers em /opt, /etc e JAR
```

## 4. Passo a passo

### 4.1 Preparar o repositório

```powershell
cd C:\Projetos\cogsi2627-1260168-1260204
git checkout main
git pull origin main
git checkout -b ca3-part2
```

### 4.2 Gerar os ficheiros de segurança

Os ficheiros foram gerados com o script `CA3/aplicar_seguranca.ps1`, que escreve os ficheiros de `CA3/ansible/` com finais de linha LF. Este script não faz parte da entrega e não deve ser incluído nos commits.

```powershell
cd CA3
powershell -NoProfile -ExecutionPolicy Bypass -File .\aplicar_seguranca.ps1
```

### 4.3 Copiar para a VM e validar a sintaxe

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\prepare.ps1
vagrant ssh app
```

```bash
cd ~/ca3/ansible
ansible-playbook -i hosts.ini site.yml --syntax-check
ansible-lint site.yml
```

Resultado obtido: sintaxe sem erros e `ansible-lint` com 0 falhas e 1 aviso (`no-handler`, justificado no `.ansible-lint`).

### 4.4 Executar o playbook

```bash
ansible-playbook -i hosts.ini site.yml
ansible-playbook -i hosts.ini site.yml
```

Na primeira execução, `db` reporta `changed=1` na pasta `/var/lib/h2`, porque o modo é corrigido pela primeira vez. A segunda execução tem de dar `changed=0` nas três VMs.

Resultado da segunda execução (validada):

```text
app   : ok=24  changed=0  failed=0  skipped=1
db    : ok=23  changed=0  failed=0  skipped=0
proxy : ok=7   changed=0  failed=0  skipped=0
```

O `skipped=1` em `app` é a compilação Gradle, que só corre quando o código muda ou o JAR não existe.

## 5. Decisões de design

### 5.1 Grupo e permissões

- `developers` é o grupo que pode aceder aos artefactos de desenvolvimento: o JAR e a configuração da Bookstore em `/opt/bookstore` e `/etc/bookstore` (`root:developers`, `0750` e `0640`), e a base de dados em `/var/lib/h2` (`h2:developers`, `2770`).
- As contas de serviço `bookstore` e `h2` entram no grupo `developers` como grupo suplementar. Sem isto não conseguiriam ler o JAR nem escrever na base de dados. Não recebem acesso adicional a outros ficheiros.
- `devuser` pertence a `developers` e não é dono de nenhum dos diretórios.

### 5.2 Modo simbólico em `/var/lib/h2`

Usámos `mode: 'u=rwX,g=rwXs,o='` em vez de `2770`. O `X` maiúsculo só acrescenta execução a diretórios, e o `s` no grupo ativa o setgid, para que os ficheiros novos herdem o grupo `developers`.

### 5.3 Máscara do H2 (`UMask`)

Como o H2 cria os ficheiros da base de dados com permissões base `0777`, um `recurse` no Ansible voltava a estragar o modo a cada execução, e a tarefa nunca ficava idempotente. A solução foi um drop-in do `systemd`, `/etc/systemd/system/h2-server.service.d/umask.conf`, com `UMask=0007`. Com isto a segunda execução ficou sem alterações.

Limitação conhecida: o H2 mantém o bit de execução nos ficheiros criados (`-rwxrwx---`). Como `o` continua sem permissões e o grupo é o pretendido, não há exposição a utilizadores fora de `developers`. Corrigir isto exigiria `UMask=0117` ou ajustes à forma como o H2 cria ficheiros, e ficou fora do âmbito.

### 5.4 Ordem dos plays

A role `security` corre primeiro, com `hosts: database:application`. Assim o grupo `developers` existe antes das roles `h2` e `bookstore` o usarem como grupo suplementar.

## 6. Validação

### 6.1 Acesso à base de dados

```bash
ansible database -i hosts.ini -b -m shell -a "sudo -u devuser cat /var/lib/h2/bookstore.mv.db >/dev/null && echo DEVUSER_OK || echo DEVUSER_DENIED; sudo -u nobody cat /var/lib/h2/bookstore.mv.db >/dev/null 2>&1 && echo NOBODY_OK || echo NOBODY_DENIED"
```

Resultado:

```text
DEVUSER_OK
NOBODY_DENIED
```

### 6.2 Grupos e permissões

```bash
id devuser
getent group developers
id bookstore
sudo cat /etc/security/faillock.conf
grep -E "minlen|minclass" /etc/security/pwquality.conf
```

Resultado:

```text
uid=1002(devuser) gid=1003(devuser) groups=1003(devuser),1002(developers)
developers:x:1002:devuser,bookstore
uid=997(bookstore) gid=998(bookstore) groups=998(bookstore),1002(developers)
deny = 5
unlock_time = 600
minlen = 12
minclass = 3
```

### 6.3 Aplicação

```bash
curl -i http://localhost/books
```

O health check do playbook confirma `HTTP 200` em `/books` através do Nginx.

## 7. O que não foi testado

- **Política de passwords (pwquality, pwhistory):** a conta `devuser` fica sem password (`!`), por omissão, porque nenhuma password foi definida. Para testar, é preciso gerar um hash com `mkpasswd --method=sha-512`, passá-lo com `-e dev_user_password_hash=...`, e tentar alterar a password para uma que viole a política.
- **Bloqueio (faillock):** não foram feitas cinco tentativas falhadas para confirmar o bloqueio de 10 minutos.

## 8. Diferenças entre distribuições (PAM)

Os ficheiros `common-auth`, `common-account` e `common-password` foram escritos com a base do Ubuntu 22.04 (Jammy). Noutras distribuições:

- **Debian e Ubuntu:** usam `pam-auth-update`, e os módulos ficam em `/etc/pam.d/common-*`. A ordem `[success=1 default=ignore]` depende da versão do `pam_unix`.
- **RHEL, Rocky, Fedora:** usam `/etc/pam.d/system-auth` e `password-auth`, e `pam_faillock` já vem configurado com `authselect`. Os ficheiros desta role não se aplicam diretamente.
- **Alpine:** usa `linux-pam` com ficheiros de configuração diferentes, e não tem `pam_faillock` por omissão.

Para este CA3, a base é o Ubuntu 22.04 da box `ubuntu/jammy64`.

## 9. Pendente nesta parte

- Testar a política de passwords com `devuser` e uma password real.
- Testar o bloqueio com cinco tentativas falhadas.
- Análise e implementação da alternativa de gestão de configuração (secção separada do README).
- Autoavaliação de cada membro, a preencher no fecho do CA3.

## 10. Commits sugeridos

```bash
git add CA3/ansible/roles/security CA3/ansible/site.yml CA3/ansible/.ansible-lint
git commit -m "ca3: adicionar role security (grupo developers, devuser e politica PAM)"
git add CA3/ansible/roles/h2/tasks/main.yml CA3/ansible/roles/bookstore/tasks/main.yml
git commit -m "ca3: restringir H2 e Bookstore ao grupo developers"
git add CA3/README.md
git commit -m "docs: README da parte de seguranca do CA3"
```

O `aplicar_seguranca.ps1` não deve ser adicionado.
