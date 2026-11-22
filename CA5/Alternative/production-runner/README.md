# Runner de produção com chave exclusivamente local

Esta configuração prepara um runner GitHub Actions Linux em Docker, com a etiqueta `ca5-production`. Usa a imagem oficial `actions-runner` 2.338.2, identificada por digest, e acrescenta Python, venv e SSH. Em 22/11/2026 foi registado como `ca5-production-local`, com ID 21, usando um token temporário emitido pela conta proprietária. A ligação ao GitHub, o estado de espera por jobs e o acesso SSH à VM foram confirmados. O proprietário confirmou o estado Idle/Online e a etiqueta no GitHub.

A chave da VM fica em `CA5/Part2/.local/secrets/production_key` e é montada apenas neste container. O workflow copia-a temporariamente para o diretório da execução e elimina a cópia em `always()`. Não é necessário enviar a chave para um Secret GitHub. O ficheiro e o token de registo são ignorados pelo Git.

O registo prepara a ligação ao GitHub sem exigir alterações na main. O job de deploy continua condicionado a um push na main. Nesta etapa não foi executado qualquer job GitHub no runner nem feito deploy; essa validação fica para a integração autorizada.

### Preparação e registo

O runner corre no computador do grupo, dentro de um container Linux. O proprietário do repositório obtém o token de registo; a conta local de trabalho pode continuar a ser a conta colaboradora habitual.

1. Abrir o Docker Desktop e aguardar que o motor esteja em execução.
2. A partir de `CA5/Part2`, arrancar a VM existente com `vagrant up production --provider virtualbox` e confirmar a porta com `vagrant port production --guest 22`.
3. Na conta proprietária `JP-142004`, abrir **Settings → Actions → Runners → New self-hosted runner**, escolher **Linux** e **x64**.
4. Na secção Configure, copiar apenas o valor que aparece depois de `--token`. Não é necessário executar no Windows os comandos Linux mostrados nessa página, porque a imagem Docker já contém o runner.
5. Transferir esse token temporário por um canal privado para o computador que vai executar o runner e guardá-lo em `CA5/Part2/.local/secrets/github_runner_registration_token`, sem extensão adicional. O token visível no computador do proprietário não fica automaticamente disponível no outro computador.
6. Confirmar que o ficheiro tem apenas o token, guardar e executar o comando seguinte a partir da raiz do repositório.

```powershell
.\CA5\Alternative\production-runner\start.ps1 -UseExistingRegistrationToken
```

Para editar o ficheiro no Windows, pode usar-se `notepad CA5\Part2\.local\secrets\github_runner_registration_token`, a partir da raiz. O token é colado no Bloco de Notas e guardado com Ctrl+S, sem o colocar no chat, num comando com o valor literal ou num ficheiro versionado. O script valida que não está vazio e normaliza BOM e finais de linha Windows para UTF-8 sem BOM antes de o montar no container. A pasta `.local/` está ignorada pelo Git.

Se a sessão GitHub CLI no próprio computador pertencer ao proprietário, também pode ser usado:

```powershell
.\CA5\Alternative\production-runner\start.ps1
```

Sem `-UseExistingRegistrationToken`, o script pede um token temporário através da sessão GitHub CLI do proprietário. Com a opção, usa o ficheiro local fornecido. Nos dois casos ajusta as variáveis GitHub `CA5_PRODUCTION_HOST` e `CA5_PRODUCTION_SSH_PORT` ao encaminhamento Vagrant e arranca o container. Foram usados `host.docker.internal` e a porta 2222. A conta colaboradora tinha recebido HTTP 403 ao tentar gerir runners; o token emitido pelo proprietário permitiu o registo sem mudar as permissões dessa conta.

### Confirmação e limites

O arranque do container, por si só, não prova o registo. Foi confirmada a ligação ao GitHub, a aceitação do registo e a mensagem de espera por jobs. Foi lida apenas a identificação pública em `.runner`, sem ler o ficheiro `.credentials`. Uma chamada SSH `true`, a partir do próprio container, confirmou acesso à VM sem alterar a aplicação. Os resultados, sem token nem chave privada, estão em [12-runner-registration.json](../evidence/12-runner-registration.json).

O proprietário confirmou no GitHub o nome `ca5-production-local`, estado Idle/Online e etiqueta `ca5-production`. Os logs detalhados do runner não são enviados diretamente para stdout. O token e a chave SSH são montados como secrets locais; não entram na imagem Docker ou nos Secrets do GitHub.

O runner é efémero: aceita um job e termina. Para outra execução, volta a iniciar com um novo token. Mantém a imagem atualizada, porque a atualização automática foi desativada para preservar a versão usada na demonstração. As execuções têm acesso à chave local; usa este runner apenas para código de confiança do grupo e liga-o durante a demonstração.

Para parar:

```powershell
docker compose -f CA5/Alternative/production-runner/compose.yaml stop
```

Esta preparação não altera a condição do deploy: o workflow só implanta num push na main. A validação da branch `ca5-part2` ignora o deploy.

Em 22/11/2026, este runner executou com sucesso o job de deploy da [main, execução 45041352249](https://github.com/JP-142004/cogsi2627-1260168-1260204/actions/runs/45041352249). Preparou Python 3.13 e Ansible, usou a chave local, implantou a imagem Docker Hub, verificou a saúde e removeu a cópia temporária da chave. Terminou com código zero depois desse único job. O relatório e os logs estão na [evidência 15](../evidence/15-github-main-45041352249.json). Um novo deploy exige novo registo do runner; o Jenkins fica como ferramenta ativa para a VM após a demonstração.

Referências: [registar runners e permissões necessárias](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners), [imagem oficial](https://github.com/actions/runner/pkgs/container/actions-runner), [release 2.338.2](https://github.com/actions/runner/releases/tag/v2.338.2).
