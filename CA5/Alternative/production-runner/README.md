# Runner de produção com chave exclusivamente local

Esta configuração prepara um runner GitHub Actions Linux em Docker, com a etiqueta `ca5-production`. Usa a imagem oficial `actions-runner` 2.338.2, identificada por digest, e acrescenta Python, venv e SSH. A imagem foi construída localmente; o registo no GitHub está pendente de acesso administrativo ao repositório.

A chave da VM fica em `CA5/Part2/.local/secrets/production_key` e é montada apenas neste container. O workflow copia-a temporariamente para o diretório da execução e elimina a cópia em `always()`. Não é necessário enviar a chave para um Secret GitHub. O ficheiro e o token de registo são ignorados pelo Git.

Quando a integração e o deploy na main forem autorizados, o administrador pode executar, a partir da raiz:

```powershell
.\CA5\Alternative\production-runner\start.ps1
```

O script emite um token temporário de registo através da sessão GitHub do administrador, sem o mostrar, ajusta host e porta SSH ao encaminhamento Vagrant e arranca o container. A conta usada nesta preparação tem permissão de push, mas a API de runners respondeu HTTP 403; não foi tentado contornar essa permissão.

Se o administrador fornecer o token através do ficheiro local `.local/secrets/github_runner_registration_token`, executa `start.ps1 -UseExistingRegistrationToken` enquanto o token estiver válido. Não o coloques em issues, documentos ou mensagens.

O runner é efémero: aceita um job e termina. Para outra execução, volta a iniciar com um novo token. Mantém a imagem atualizada, porque a atualização automática foi desativada para preservar a versão usada na demonstração. As execuções têm acesso à chave local; usa este runner apenas para código de confiança do grupo e liga-o durante a demonstração.

Para parar:

```powershell
docker compose -f CA5/Alternative/production-runner/compose.yaml stop
```

Esta preparação não altera a condição do deploy: o workflow só implanta num push na main. A validação da branch `ca5-part2` ignora o deploy.

Referências: [registar runners e permissões necessárias](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners), [imagem oficial](https://github.com/actions/runner/pkgs/container/actions-runner), [release 2.338.2](https://github.com/actions/runner/releases/tag/v2.338.2).
