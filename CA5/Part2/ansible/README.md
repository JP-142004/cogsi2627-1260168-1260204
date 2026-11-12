# Ansible da VM de produção

Vais usar estes playbooks para preparar a VM e implantar a imagem identificada pela tag do pipeline. O Jenkins e a futura alternativa GitHub Actions podem chamar os mesmos ficheiros.

| Ficheiro | Função |
|---|---|
| `provision.yml` | Instalar e iniciar Docker, incluindo a biblioteca Python necessária aos módulos |
| `deploy.yml` | Validar parâmetros, preparar Docker, autenticar, obter a imagem, substituir o container e verificar o resultado |
| `verify.yml` | Confirmar a imagem, o utilizador, o estado saudável do container e o endpoint HTTP |
| `hosts.ini` | VM `192.168.56.20`, utilizador `vagrant`, Python 3 e política SSH `accept-new` |
| `group_vars/production.yml` | Parâmetros de imagem, nome do container, porta e limite de memória |
| `requirements.yml` | Collection `community.docker` na versão validada 4.8.9 |
| `Dockerfile` | Controlador Linux para executar Ansible a partir do Windows |

## 1. Preparar o controlador

Se já tens Ansible num sistema Linux, instala a collection e valida os playbooks:

```bash
cd CA5/Part2/ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i hosts.ini --syntax-check provision.yml deploy.yml verify.yml
```

O controlador usado nos testes locais é construído com Python 3.12, Ansible Core 2.17.14 e OpenSSH. A partir desta pasta, podes construí-lo e repetir a validação no PowerShell:

```powershell
docker build --tag cogsi-ca5-ansible:local .
$ansiblePath = (Get-Location).Path
docker run --rm --memory 384m --mount "type=bind,source=$ansiblePath,target=/work,readonly" cogsi-ca5-ansible:local -i hosts.ini --syntax-check provision.yml deploy.yml verify.yml
```

A validação sintática confirma que os playbooks e módulos são reconhecidos; não comprova acesso SSH, autenticação Docker Hub ou deploy numa VM.

## 2. Preparar o acesso SSH

Arranca a VM com `vagrant up production --provider virtualbox`, em `CA5/Part2`. O Vagrant gera a chave privada em `.vagrant/machines/production/virtualbox/private_key`. Nunca a guardes no Git, nas evidências ou numa imagem Docker.

Num controlador Linux, copia a chave para um local privado, aplica permissões 600 e fornece esse caminho a `--private-key`. No Jenkins, guarda-a como credencial SSH e deixa o pipeline fornecer o caminho temporário.

```bash
ansible-playbook -i hosts.ini provision.yml --private-key "$SSH_KEY"
```

No Windows deste trabalho, o controlador Docker não alcançou diretamente a rede host-only, mas conseguiu aceder à porta SSH encaminhada pelo Vagrant através de `host.docker.internal`. Para reproduzir o provisionamento a partir de `CA5/Part2`, usa:

```powershell
$ansiblePath = (Resolve-Path 'ansible').Path
$keyPath = (Resolve-Path '.vagrant/machines/production/virtualbox/private_key').Path
$sshPort = (vagrant port production --guest 22).Trim()
$bootstrap = 'mkdir -p /root/.ssh && cp /vagrant-key /root/.ssh/production_key && chmod 600 /root/.ssh/production_key && exec ansible-playbook -i hosts.ini provision.yml --private-key /root/.ssh/production_key -e ansible_host=host.docker.internal -e ansible_port=' + $sshPort

docker run --rm --memory 384m `
  --mount "type=bind,source=$ansiblePath,target=/work,readonly" `
  --mount "type=bind,source=$keyPath,target=/vagrant-key,readonly" `
  --entrypoint sh cogsi-ca5-ansible:local -c $bootstrap
```

A chave é montada apenas para leitura, copiada para dentro do container e o ficheiro recebe permissões 600. É eliminada com o container no fim. O inventário mantém o IP privado; a substituição de host e porta aplica-se apenas a este comando.

A opção `StrictHostKeyChecking=accept-new` aceita a primeira chave apresentada pela VM e recusa alterações a uma chave já conhecida. O inventário contém esta opção explicitamente, porque o Ansible pode ignorar um `ansible.cfg` numa pasta Windows montada em `/mnt/c`.

## 3. Fornecer a imagem e as credenciais

O deploy lê estas variáveis do ambiente do controlador:

| Variável | Conteúdo |
|---|---|
| `BOOKSTORE_IMAGE_REPOSITORY` | Nome completo do repositório Docker Hub, por exemplo `utilizador/ca5-bookstore` |
| `BOOKSTORE_IMAGE_TAG` | Tag concreta produzida pelo pipeline |
| `DOCKERHUB_USERNAME` | Utilizador Docker Hub |
| `DOCKERHUB_TOKEN` | Token de acesso, fornecido pelo gestor de credenciais |

Não uses `latest` para implantar uma versão. O playbook rejeita essa tag e parâmetros de imagem vazios ou malformados antes de executar alterações na VM.

Num controlador Linux, com as variáveis já fornecidas pelo gestor de credenciais, executa:

```bash
ansible-playbook -i hosts.ini deploy.yml --private-key "$SSH_KEY"
ansible-playbook -i hosts.ini verify.yml --private-key "$SSH_KEY"
```

Os segredos não são passados como argumentos `-e`. A autenticação usa uma pasta temporária privada na VM e a tarefa de login tem `no_log: true`. O bloco `always` remove a pasta de autenticação mesmo se o pull falhar.

Se usares o controlador Docker, acrescenta `--env DOCKERHUB_USERNAME --env DOCKERHUB_TOKEN --env BOOKSTORE_IMAGE_REPOSITORY --env BOOKSTORE_IMAGE_TAG` ao comando `docker run`, com essas variáveis já fornecidas ao processo pelo gestor de credenciais, e troca `provision.yml` por `deploy.yml` no comando interno. Para `verify.yml`, só precisas das duas variáveis da imagem e da chave SSH. Não escrevas os valores dos segredos no histórico da consola.

## 4. Comportamento e limitações

O playbook obtém a nova imagem antes de remover o container existente. Se a autenticação ou o pull falharem, o container anterior continua a correr. Depois de obter a imagem, para e remove o container anterior e cria `ca5-bookstore`, publicando a porta 8080 e usando `restart_policy: unless-stopped`.

O container tem um limite de 512 MB. O Java recebe `-XX:MaxRAMPercentage=60.0`, reservando memória para a JVM e as restantes necessidades do processo. A verificação aguarda pelo estado Docker `healthy`, com 36 repetições espaçadas por cinco segundos, confirma a referência exata da imagem e UID/GID 10001 e exige HTTP 200 com `status: UP` em `/actuator/health`.

Este é um deploy por substituição, com uma breve interrupção. Se o novo container não arrancar, o playbook falha; não oferece rollback automático. O H2 é em memória e os dados não persistem entre substituições.

O provisionamento pode ser repetido para garantir pacotes e serviço ativos. O deploy substitui intencionalmente o container em cada execução, mesmo quando a tag é igual, pelo que não é idempotente nesse passo.

## 5. Referências

- [community.docker.docker_login](https://docs.ansible.com/projects/ansible/latest/collections/community/docker/docker_login_module.html)
- [community.docker.docker_image](https://docs.ansible.com/projects/ansible/latest/collections/community/docker/docker_image_module.html)
- [community.docker.docker_container](https://docs.ansible.com/projects/ansible/latest/collections/community/docker/docker_container_module.html)
