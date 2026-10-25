# CA3 - Provisionamento com Ansible e Alternativa em Puppet

Este documento descreve a parte de segurança do CA3, desenvolvida sobre a infraestrutura Ansible do Luiz (H2, Bookstore e Nginx), e a alternativa de gestão de configuração implementada em Puppet (modo masterless). O objetivo é que a entrega possa ser reproduzida passo a passo e que os resultados sejam os obtidos nas VMs.

## Índice

1. Requisitos cobertos
2. Pré-requisitos
3. Estrutura dos ficheiros
4. Parte 1: Ansible (passo a passo)
5. Decisões de design (Ansible)
6. Validação (Ansible)
7. Limitações (Ansible)
8. Diferenças entre distribuições (PAM)
9. Parte 2: Alternativa em Puppet
10. Commits e entrega

## 1. Requisitos cobertos

| Requisito | Onde | Estado |
|-----------|------|--------|
| Grupo `developers` e utilizador `devuser` em `app` e `db` | `roles/security/tasks/accounts.yml` (Ansible) e `modules/security` (Puppet) | Feito e validado nas duas ferramentas |
| `devuser` pertence a `developers` | `accounts.yml` e `init.pp` | Feito e validado |
| Aplicação e base de dados em diretórios restritos a `developers` | `roles/bookstore`, `roles/h2` e `init.pp` | Feito e validado |
| Contas de serviço `bookstore` e `h2` com acesso necessário | Grupo suplementar `developers` | Feito e validado |
| Mínimo de 12 caracteres | `pwquality.conf` (`minlen = 12`) | Validado (teste 6.4) |
| Pelo menos 3 de 4 classes de caracteres | `pwquality.conf` (`minclass = 3`) | Validado (teste 6.4) |
| Histórico de 5 passwords | `pam_pwhistory` (`remember=5`) | Validado (teste 6.5) |
| Bloqueio de 10 minutos após 5 falhas | `pam_faillock` (`deny=5`, `unlock_time=600`) | Validado (teste 6.6) |
| `no_log: true` em tarefas sensíveis | `accounts.yml`, `bookstore`, `h2` | Feito (Ansible) |
| Idempotência (segunda execução com 0 alterações) | Playbook Ansible e `puppet apply` | Validado nas duas ferramentas |
| Alternativa implementada e analisada | `ansible/puppet/` e secção 9 | Feito, com limitações (secção 9.7) |

## 2. Pré-requisitos

- Vagrant e VirtualBox instalados no Windows.
- Repositório clonado e branch `ca3-part2` criada a partir de `main`.
- VMs `db`, `app` e `proxy` criadas pelo `prepare.ps1`.

## 3. Estrutura dos ficheiros

```text
CA3/
├── Vagrantfile
├── prepare.ps1                     # Copia ansible/ para a VM app e prepara o controlador
└── ansible/
    ├── hosts.ini                   # Inventário: database, application, reverse_proxy
    ├── site.yml                    # Play de segurança primeiro, depois serviços
    ├── .ansible-lint               # no-handler como aviso (justificado)
    ├── roles/
    │   ├── security/
    │   │   ├── defaults/main.yml
    │   │   ├── tasks/
    │   │   │   ├── main.yml            # import_tasks dos três ficheiros abaixo
    │   │   │   ├── accounts.yml        # grupo developers e devuser
    │   │   │   ├── password_policy.yml # pwquality e faillock
    │   │   │   └── pam.yml             # copia common-auth, common-account, common-password
    │   │   └── files/
    │   │       ├── common-auth
    │   │       ├── common-account
    │   │       └── common-password
    │   ├── h2/tasks/main.yml           # alterado: grupo developers, setgid e UMask
    │   └── bookstore/tasks/main.yml    # alterado: grupo developers em /opt, /etc e JAR
    └── puppet/                         # Alternativa (secção 9)
        ├── manifests/site.pp
        └── modules/security/
            ├── manifests/init.pp
            └── files/common-auth, common-account, common-password
```

Os scripts `aplicar_seguranca.ps1` e `aplicar_puppet.ps1` são geradores de ficheiros, ficam em `CA3/` e não fazem parte da entrega.

## 4. Parte 1: Ansible (passo a passo)

### 4.1 Preparar o repositório

```powershell
cd C:\Projetos\cogsi2627-1260168-1260204
git checkout main
git pull origin main
git checkout -b ca3-part2
```

### 4.2 Gerar os ficheiros

```powershell
cd CA3
powershell -NoProfile -ExecutionPolicy Bypass -File .\aplicar_seguranca.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\aplicar_puppet.ps1
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

Na primeira execução, `db` reporta alterações nas permissões de `/var/lib/h2`, porque o modo é corrigido pela primeira vez. A segunda execução tem de dar `changed=0` nas três VMs.

Primeira execução depois da aplicação do Puppet (secção 9): `app` e `db` reportaram `changed=4`, porque o Ansible reescreveu os ficheiros PAM e de configuração que o Puppet tinha escrito. Esta é a interação entre os dois gestores descrita na secção 9.6.

Segunda execução (validada):

```text
app   : ok=24  changed=0  failed=0  skipped=1
db    : ok=23  changed=0  failed=0  skipped=0
proxy : ok=7   changed=0  failed=0  skipped=0
```

O `skipped=1` em `app` é a compilação Gradle, que só corre quando o código muda ou o JAR não existe.

## 5. Decisões de design (Ansible)

### 5.1 Grupo e permissões

- `developers` é o grupo que pode aceder aos artefactos de desenvolvimento: o JAR e a configuração da Bookstore em `/opt/bookstore` e `/etc/bookstore` (`root:developers`, `0750` e `0640`), e a base de dados em `/var/lib/h2` (`h2:developers`).
- As contas de serviço `bookstore` e `h2` entram no grupo `developers` como grupo suplementar. Sem isto não conseguiriam ler o JAR nem escrever na base de dados. Não recebem acesso adicional a outros ficheiros.
- `devuser` pertence a `developers` e não é dono de nenhum dos diretórios.

### 5.2 Modo simbólico em `/var/lib/h2`

Usámos `mode: 'u=rwX,g=rwXs,o='` em vez de `2770`. O `X` maiúsculo só acrescenta execução a diretórios, e o `s` no grupo ativa o setgid, para que os ficheiros novos herdem o grupo `developers`.

### 5.3 Máscara do H2 (`UMask`)

O H2 cria os ficheiros da base de dados com permissões base `0777`. Um `recurse` no Ansible voltava a estragar o modo a cada execução, e a tarefa nunca ficava idempotente. A solução foi um drop-in do `systemd`, `/etc/systemd/system/h2-server.service.d/umask.conf`, com `UMask=0007`. Com isto a segunda execução ficou sem alterações.

### 5.4 Ordem dos plays

A role `security` corre primeiro, com `hosts: database:application`. Assim o grupo `developers` existe antes das roles `h2` e `bookstore` o usarem como grupo suplementar.

## 6. Validação (Ansible)

### 6.1 Acesso à base de dados

```bash
ansible database -i hosts.ini -b -m shell -a "sudo -u devuser cat /var/lib/h2/bookstore.mv.db >/dev/null && echo DEVUSER_OK || echo DEVUSER_DENIED; sudo -u nobody cat /var/lib/h2/bookstore.mv.db >/dev/null 2>&1 && echo NOBODY_OK || echo NOBODY_DENIED"
```

Resultado obtido: `DEVUSER_OK` e `NOBODY_DENIED`.

### 6.2 Grupos e permissões

```bash
id devuser
getent group developers
id bookstore
sudo cat /etc/security/faillock.conf
grep -E "minlen|minclass" /etc/security/pwquality.conf
```

Resultado obtido na `app`:

```text
uid=1002(devuser) gid=1003(devuser) groups=1003(devuser),1002(developers)
developers:x:1002:devuser,bookstore
minlen = 12
minclass = 3
deny = 5
unlock_time = 600
fail_interval = 900
```

O `faillock.conf` foi lido depois da primeira execução do Ansible, por isso traz o cabeçalho `# Gerido pelo Ansible`.

### 6.3 Aplicação

```bash
curl -i http://localhost/books
```

Resultado obtido: `HTTP/1.1 200` em `http://192.168.56.20/books`, a partir da `app`. O Nginx está na VM `proxy`, por isso o `curl` para `localhost` na `app` falha com `Connection refused`, o que é esperado.

### 6.4 Política de complexidade

A password base de `devuser` foi definida com `sudo passwd devuser`. As tentativas de alteração foram feitas com `sudo -u devuser passwd`, porque a política PAM só se aplica a utilizadores não-root.

| Tentativa | Resultado |
|-----------|-----------|
| `curta` (menos de 12 caracteres) | Rejeitada: `The password is shorter than 12 characters` |
| `minusculas2026` (uma classe) | Rejeitada: `The password contains less than 3 character classes` |
| Igual à password atual | Rejeitada: `The password is the same as the old one` |
| `Outra#Senha2026` | Aceite |

### 6.5 Histórico de passwords

Sequência de mudanças feitas por `devuser`, com `remember=5`:

| Passo | Alteração | Resultado |
|-------|-----------|-----------|
| 1 | `Outra#Senha2026` → `Terceira#Senha26` | Aceite |
| 2 | `Terceira#Senha26` → `Outra#Senha2026` | Rejeitada (no histórico) |
| 3 | → `Quarta#Senha2026` | Aceite |
| 4 | → `Quinta#Senha2026` | Aceite |
| 5 | → `Sexta#Senha2026` | Aceite |
| 6 | → `Setima#Senha2026` | Aceite |
| 7 | → `Outra#Senha2026` | Aceite: já tinha saído da janela de 5 |

Verificação do ficheiro `/etc/security/opasswd`: `Quarta`, `Quinta`, `Sexta` e `Setima` estão guardadas. Depois desta sequência, a password atual é `Outra#Senha2026`, e as duas tentativas seguintes foram recusadas com `Password has been already used`:

- `Outra#Senha2026` → `Quarta#Senha2026`: rejeitada
- `Outra#Senha2026` → `Setima#Senha2026`: rejeitada

### 6.6 Bloqueio após falhas

Cinco tentativas com password errada, seguidas de uma tentativa com a password correta, feitas com `pamtester` (service `login`) através de `sudo`:

Resultado esperado: após as cinco falhas, a mensagem `The account is locked due to 5 failed logins.` e a tentativa com a password correta é recusada enquanto a conta estiver bloqueada. O `sudo faillock --user devuser` regista as cinco falhas. Depois do teste, a conta foi desbloqueada com `sudo faillock --user devuser --reset`.

## 7. Limitações (Ansible)

- **H2 e bit de execução:** os ficheiros da base de dados ficam com `rwxrwx---` (ver 5.3). Sem impacto na confidencialidade para utilizadores fora de `developers`.
- **Distribuição:** os ficheiros PAM foram escritos com a base do Ubuntu 22.04 (Jammy), usada pela box `ubuntu/jammy64`. Não são portáveis diretamente para outras famílias de distribuições (ver secção 8).
- **Password do `devuser`:** a password foi definida manualmente com `passwd`, e não pelo playbook. O `update_password: on_create` evita que o playbook a volte a alterar nas execuções seguintes.
- **Sudo e PAM:** as alterações ao PAM afetam também `sudo` e `su`.
## 8. Diferenças entre distribuições (PAM)

Os ficheiros `common-auth`, `common-account` e `common-password` foram escritos com a base do Ubuntu 22.04. Noutras distribuições:

- **Debian e Ubuntu:** usam `pam-auth-update`, e os módulos ficam em `/etc/pam.d/common-*`. A ordem `[success=1 default=ignore]` depende da versão do `pam_unix`.
- **RHEL, Rocky, Fedora:** usam `/etc/pam.d/system-auth` e `password-auth`, e `pam_faillock` já vem configurado com `authselect`. Os ficheiros desta role não se aplicam diretamente.
- **Alpine:** usa `linux-pam` com ficheiros de configuração diferentes, e não tem `pam_faillock` por omissão.

Para este CA3, a base é o Ubuntu 22.04 da box `ubuntu/jammy64`.

## 9. Parte 2: Alternativa em Puppet

Esta secção analisa alternativas de gestão de configuração ao Ansible, desenha a solução para os requisitos de segurança com a ferramenta escolhida e documenta a implementação e os testes. A escolha foi o **Puppet em modo masterless** (`puppet apply`), sem servidor central.

### 9.1 Análise comparativa

| Critério | Ansible (base) | Puppet (escolhida) | Chef | SaltStack |
|----------|----------------|--------------------|------|-----------|
| Arquitetura | Sem agente, via SSH | Agente com servidor, ou masterless (`puppet apply`) | Agente com servidor, ou masterless (`chef-solo`) | Agente com master, ou masterless (`salt-call --local`) |
| Linguagem | YAML com Jinja2 | DSL declarativa própria | Ruby (DSL) | YAML com Jinja2 |
| Modelo | Procedural por tarefas, com declaração de estado | Declarativo: descreve o estado final e o motor calcula as alterações | Procedural, com recursos Ruby | Declarativo por estados, com execução por tarefas |
| Idempotência | Responsabilidade dos módulos e das tarefas | Garantida pelos tipos de recurso (`user`, `group`, `file`) | Garantida pelos recursos | Garantida pelos estados |
| Gestão de segredos | `ansible-vault` | Hiera com eyaml (ou módulos externos) | Encrypted data bags | Pillar cifrado |
| Verificação antes de aplicar | `--check` (limitado) | `--noop` completo, com relatório por recurso | `why-run` | `test=True` |
| Ordem de execução | Ordem das tarefas, com `notify` e handlers | Grafo de dependências (`require`, `before`) | Ordem explícita e notificações | Requisitos entre estados (`require`) |
| Módulos PAM | Não há módulo nativo genérico; usa-se `copy` ou `lineinfile` | Módulo `pam` no Forge (não incluído no núcleo) | Recipe comunitária | Não existe estado `pam` no núcleo |
| Curva de aprendizagem | Baixa | Média (DSL própria) | Alta (Ruby) | Média |
| Instalação no alvo | Só Python no alvo | Agente Puppet em cada VM | Agente Chef em cada VM | Agente Salt ou masterless |

As conclusões são estas. O Ansible é mais simples de usar e não precisa de agente, mas a sua idempotência depende de cada tarefa estar bem escrita, e não existe um tipo genérico para PAM. O Puppet tem tipos de recurso que verificam o estado real antes de agir, e o `--noop` mostra o que mudaria sem alterar nada. Para os requisitos de segurança (utilizadores, grupos, permissões e ficheiros PAM), o Puppet expressa o estado final de forma mais direta. Chef exige mais conhecimento de Ruby e Salt tem uma comunidade menor neste contexto. Por isso escolhemos o Puppet, em modo masterless, para não introduzir um servidor central.

### 9.2 Desenho da solução

Os requisitos são os mesmos da parte Ansible.

| Requisito | Recurso Puppet |
|-----------|----------------|
| Grupo `developers` | `group { 'developers': }` |
| Utilizador `devuser` no grupo | `user { 'devuser': groups => ['developers'] }` |
| Complexidade e histórico | `file` para `/etc/security/pwquality.conf` e `common-password` |
| Bloqueio após 5 falhas | `file` para `/etc/security/faillock.conf`, `common-auth` e `common-account` |
| Permissões da base de dados | `file { '/var/lib/h2': mode => '2770' }`, sem `recurse` |
| Contas de serviço | `user { 'h2': }` e `user { 'bookstore': }` com `groups => ['developers']` |
| Diretórios da aplicação | `file { ['/opt/bookstore', '/etc/bookstore']: group => 'developers' }` |
| Escolha por máquina | `case $facts['networking']['hostname']`, com `/db$/` e `/app$/` |

Estrutura do código, em `CA3/ansible/puppet/`:

```text
puppet/
├── manifests/site.pp                    # include security
└── modules/security/
    ├── manifests/init.pp                # classe security
    └── files/common-auth, common-account, common-password
```

### 9.3 Instalação do Puppet nas VMs

Na `app`:

```bash
sudo apt-get install -y puppet
```

Na `db`, a instalação foi feita a partir do controlador:

```bash
ansible database -i hosts.ini -b -m apt -a "name=puppet state=present update_cache=true"
```

Versão instalada: `puppet 5.5.22` (pacote do Ubuntu 22.04). Esta versão já não tem suporte da Puppet, por isso a alternativa é uma demonstração, não uma recomendação para produção.

### 9.4 Validação e simulação

```bash
cd ~/ca3/ansible/puppet
puppet parser validate manifests/site.pp modules/security/manifests/init.pp
sudo puppet apply --noop --modulepath=modules manifests/site.pp
```

### 9.5 Aplicação e idempotência

```bash
sudo puppet apply --modulepath=modules manifests/site.pp
sudo puppet apply --modulepath=modules manifests/site.pp
```

Resultado na `app`, primeira execução: os ficheiros PAM e de configuração foram reescritos para a versão Puppet (`content changed`). Segunda execução: sem alterações e sem erros.

Resultado na `db`, primeira execução: os mesmos ficheiros foram reescritos, e a conta `h2` e a pasta `/var/lib/h2` foram criadas ou corrigidas. Segunda execução: sem alterações e sem erros.

Erro encontrado: na primeira aplicação na `app`, o Puppet tentou alterar a home da conta `bookstore` para `/nonexistent`, e o `usermod` falhou porque o processo da aplicação estava em execução (`usermod: user bookstore is currently used by process`). A correção foi retirar a propriedade `home` dos recursos `user`. Depois da correção, as execuções passaram sem erros.

### 9.6 Diferenças observadas em relação ao Ansible

1. **Dois gestores para os mesmos ficheiros.** O Ansible e o Puppet escrevem os mesmos ficheiros PAM e de configuração, com cabeçalhos diferentes (`Gerido pelo Ansible` e `Gerido pelo Puppet`). Cada execução de uma ferramenta reverte a outra, e o resultado é um estado instável. Numa implementação real só uma ferramenta deve gerir cada ficheiro.
2. **Modo de escrita dos ficheiros.** O Puppet substitui o ficheiro inteiro, enquanto o Ansible com `lineinfile` altera só a linha pretendida. Por isso o `pwquality.conf` do Puppet perde os valores por omissão do Ubuntu, e o do Ansible mantém-nos.
3. **Idempotência do H2.** Com o Ansible, `recurse` causava alterações em cada execução, porque o H2 recriava ficheiros com modo `0777`. No Puppet, `mode => '2770'` sem `recurse` aplica o modo só à pasta, e o problema não aparece.
4. **Verificação prévia.** O `--noop` do Puppet mostra o estado que seria alterado, sem tocar no sistema. O Ansible tem `--check`, mas é menos fiável com tarefas que dependem de comandos.
5. **Erros de estado.** O Puppet falhou de forma clara ao tentar alterar uma conta em uso, e indicou o processo. No Ansible, a mesma situação teria de ser tratada na própria tarefa.

### 9.7 Requisitos não cobertos pela alternativa

- **Serviços H2, Bookstore e Nginx:** a instalação e o arranque continuam no Ansible. O Puppet só garante as contas, as permissões e a política de segurança. Uma implementação completa precisaria de recursos `package`, `file` e `service` para cada um.
- **Health checks:** não foram reescritos em Puppet.
- **Gestão de segredos:** a password de `devuser` é definida manualmente com `passwd`, e não é gerida pelo Puppet. Uma solução real usaria Hiera com eyaml.
- **Distribuição:** os ficheiros PAM são da base Ubuntu 22.04, como na versão Ansible.

### 9.8 Conclusão da alternativa

O Puppet em modo masterless cobre a parte de segurança do CA3, com idempotência verificada nas duas VMs. As diferenças mais importantes são o modelo declarativo, o `--noop` e a forma como os tipos de recurso tratam permissões. O principal problema observado é que dois gestores de configuração não devem tocar nos mesmos ficheiros. Para a entrega, a alternativa deve ser demonstrada separadamente da versão Ansible, e não aplicada em cima dela.

## 10. Commits e entrega

```bash
git add CA3/ansible/roles/security CA3/ansible/site.yml CA3/ansible/.ansible-lint
git commit -m "ca3: adicionar role security (grupo developers, devuser e politica PAM)" -m "Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01M2NpW2hmELTSebphGY78qg"
git add CA3/ansible/roles/h2/tasks/main.yml CA3/ansible/roles/bookstore/tasks/main.yml
git commit -m "ca3: restringir H2 e Bookstore ao grupo developers" -m "Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01M2NpW2hmELTSebphGY78qg"
git add CA3/ansible/puppet
git commit -m "ca3: implementar alternativa Puppet (masterless) para a parte de seguranca" -m "Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01M2NpW2hmELTSebphGY78qg"
git add CA3/README.md
git commit -m "docs: README do CA3 com a parte de seguranca e a alternativa Puppet" -m "Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01M2NpW2hmELTSebphGY78qg"
```

Os scripts `aplicar_seguranca.ps1` e `aplicar_puppet.ps1` não devem ser adicionados.
