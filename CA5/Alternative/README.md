# CA5 — Solução alternativa com GitHub Actions

Nesta alternativa vais executar os mesmos objetivos da Parte 2 com GitHub Actions: compilar a Bookstore, testar, construir e publicar uma imagem identificada, implantar apenas a main por Ansible e verificar a aplicação. Reutilizas a aplicação, o Dockerfile e os playbooks de `CA5/Part2`, para comparar as ferramentas de CI/CD mantendo o trabalho da aplicação equivalente.

O workflow está em [`.github/workflows/ca5-bookstore.yml`](../../.github/workflows/ca5-bookstore.yml). Essa localização é obrigatória para o GitHub o reconhecer; os ficheiros de análise e de validação local ficam nesta pasta.

## 1. Análise e comparação

O GitHub Actions foi escolhido porque o repositório já está no GitHub e permite definir os eventos e dependências dos jobs no próprio repositório. O serviço gere a execução dos jobs hospedados e a distribuição de artefactos. O deploy para a VM local continua a precisar de um runner com acesso à rede do laboratório.

| Aspeto | Jenkins da solução base | GitHub Actions da alternativa |
|---|---|---|
| Definição | Pipeline declarativo Groovy num Jenkinsfile | Workflow YAML em `.github/workflows` |
| Execução por branch | Projeto Multibranch e `checkout scm` | Evento push, contexto `github.ref` e condição no job |
| Disparo | Webhook ou Poll SCM; foi demonstrado Poll SCM local | Evento nativo do repositório, sem expor Jenkins |
| Compilação e testes | Ferramentas instaladas no nó Jenkins | Runners hospedados, com setup-java |
| Paralelismo | Bloco `parallel`, com pastas isoladas no nó | Matriz com dois jobs, cada um no seu runner |
| Distribuição | Precisa de agentes Jenkins disponíveis | Cada elemento da matriz pode ser executado num runner diferente |
| Partilha de ficheiros | `stash`/`unstash` dentro do pipeline | `upload-artifact`/`download-artifact` entre jobs |
| Resultados JUnit | Publicação integrada e histórico no Jenkins | XML/HTML como artefactos e contagens no Job Summary |
| Estados | SUCCESS, FAILURE e UNSTABLE | Testes falhados resultam em failure; não há estado UNSTABLE equivalente |
| Rastreabilidade | Artefactos e fingerprints, commit e tag de imagem | Artefactos do run, outputs, commit e tag com run ID e tentativa |
| Segredos | Jenkins Credentials | Secrets referidos apenas nos passos que os usam |
| Deploy na VM | SSH e Ansible no nó Jenkins | SSH e Ansible num self-hosted runner Linux |
| Notificação | Plugin Email Extension | SMTP com Python, executado num job final |
| Manutenção | Servidor, plugins, ferramentas, dados e agentes | Workflows e dependências; runner próprio de deploy continua a ser mantido pelo grupo |

### 1.1. Justificação e compromissos

Para este grupo, o Actions reduz a configuração necessária para reagir a commits: o evento pertence ao serviço que já aloja o repositório. Os jobs de compilação e testes podem usar runners hospedados, sem manter um servidor CI para essas tarefas.

Isso não elimina a infraestrutura local. Um runner hospedado não tem acesso direto à rede host-only da VM. A solução proposta usa um self-hosted runner Linux para o deploy. O processo desse runner e a VM têm de estar ligados; se o runner estiver indisponível, o job de deploy fica à espera de um executor compatível.

O Jenkins oferece uma apresentação JUnit mais integrada. No Actions, esta implementação publica os XML, relatórios HTML e um resumo de contagens por job, sem acrescentar uma ação de terceiros que necessite de permissões de escrita em checks. A visualização histórica não é equivalente à do Jenkins.

Também há uma diferença de resultado: no Jenkins, uma falha de testes fica UNSTABLE e bloqueia os stages seguintes; no Actions, faz falhar o job da matriz. Em ambos os casos a imagem não é publicada e não há deploy dessa versão. A notificação reflete o estado disponível na ferramenta.

## 2. Desenho da solução

```mermaid
flowchart TD
    Push[Push na main ou development] --> Assemble[Assemble e artefacto preparado]
    Assemble --> Unit[Matriz: test]
    Assemble --> Integration[Matriz: integrationTest]
    Unit --> Image[Construir imagem, arquivar metadados e publicar]
    Integration --> Image
    Image --> Condition{Push na main?}
    Condition -->|Sim| Deploy[Runner próprio: Ansible deploy]
    Deploy --> Verify[Deployment Verification]
    Condition -->|Não| NoDeploy[Sem deploy]
    Assemble --> Notify[Job final de e-mail com always]
    Unit --> Notify
    Integration --> Notify
    Image --> Notify
    Verify --> Notify
    NoDeploy --> Notify
```

### 2.1. Jobs e dependências

1. **assemble**: obtém o código, prepara Java 17, compila e empacota num artefacto o JAR executável e as classes e recursos de main.
2. **tests**: depende de assemble e usa uma matriz `task: [test, integrationTest]`, com `fail-fast: false`. Cada job recupera a compilação preparada, executa a sua tarefa, publica as contagens e arquiva os resultados, mesmo quando há uma falha.
3. **image**: só corre depois de assemble e dos dois elementos da matriz terem passado. Recupera o mesmo JAR, constrói a imagem, arquiva Dockerfile e metadados, autentica por stdin e faz push.
4. **deploy**: depende de image e exige simultaneamente `github.event_name == 'push'` e `github.ref == 'refs/heads/main'`. Corre num runner com as etiquetas `self-hosted`, `linux` e `ca5-production`, chama os playbooks e remove a chave SSH temporária em `always()`.
5. **notification**: depende dos jobs anteriores e usa `always()`, para enviar o resultado final por SMTP, incluindo quando há falhas ou deploy ignorado na development.

O evento `workflow_dispatch` permite executar manualmente a compilação e os testes; a condição do deploy não autoriza uma implantação por esse evento.

### 2.2. Identificação e artefactos

As imagens usam `gha-<branch>-<run_id>-<run_attempt>-<commit_curto>`. Assim distingues branches, repetições e reexecuções do mesmo run. O prefixo `gha` distingue esta alternativa do Jenkins.

O artefacto `prepared-app` contém um tar com o JAR e a compilação de main. Os jobs de teste e de imagem recuperam esse mesmo ficheiro. O tar também preserva os caminhos necessários para executar os testes sobre a compilação preparada, sem voltar a compilar main.

Os artefactos `junit-test` e `junit-integrationTest` guardam XML, HTML e intervalos de execução. `build-metadata` guarda o Dockerfile e `build.json`, com commit, branch, tag, data e SHA-256 do JAR. `published-image` guarda os digests observados depois do push.

## 3. Implementação

| Ficheiro | Responsabilidade |
|---|---|
| [Workflow](../../.github/workflows/ca5-bookstore.yml) | Eventos, matriz, dependências, condição de deploy, artefactos e notificação |
| [gradle.sh](../Part2/ci/gradle.sh) | Java 17, limites de memória e tempos dos comandos |
| [prepare-actions-image.py](../Part2/ci/prepare-actions-image.py) | Tag e outputs da imagem desta execução |
| [test-summary.py](../Part2/ci/test-summary.py) | Contagens JUnit no Job Summary |
| [image-metadata.py](../Part2/ci/image-metadata.py) | Dockerfile e metadados sem credenciais |
| [push-image.py](../Part2/ci/push-image.py) | Login por stdin, autenticação temporária e push |
| [deploy.sh](../Part2/ci/deploy.sh) | Chamar Ansible com imagem, host, porta e chave do gestor de credenciais |
| [notify-email.py](../Part2/ci/notify-email.py) | SMTP, TLS e resultado agregado dos jobs |
| [Playbooks](../Part2/ansible/README.md) | Instalação Docker, pull, substituição e health checks |

O workflow limita `GITHUB_TOKEN` a `contents: read`. A credencial de checkout não é persistida. As credenciais do registo são fornecidas ao passo de push e ao deploy; a chave SSH só é fornecida ao job de produção. Os scripts não imprimem os segredos nem os incluem nos artefactos.

As execuções da mesma branch são coordenadas por `concurrency`; o deploy tem ainda o grupo `ca5-production`. Isso coordena execuções do Actions, não coordena automaticamente outro servidor Jenkins. Nas demonstrações, as duas ferramentas são usadas separadamente para implantar na mesma VM.

## 4. Validação inteiramente local

Foi usado **act** para executar o workflow em Docker antes da publicação no GitHub. **actionlint** verifica a sintaxe, expressões, dependências e etiquetas do workflow. As ferramentas são instaladas apenas em `CA5/Part2/.local/tools`, com checksum SHA-256 verificado nas releases oficiais.

### 4.1. Preparar

Primeiro arranca o laboratório Jenkins, que disponibiliza também o registo local, a caixa SMTP e o túnel para a VM:

```powershell
cd CA5/Part2
.\jenkins\start-local.ps1 -RefreshScm
cd ../..
```

A partir da raiz do repositório:

```powershell
py -3 CA5/Alternative/install-local-tools.py
docker build -t cogsi-ca5-actions-runner:local -f CA5/Alternative/runner.Dockerfile CA5/Alternative
& CA5/Part2/.local/tools/actionlint.exe .github/workflows/ca5-bookstore.yml
```

O runner local reutiliza Java, Docker e Ansible da imagem Jenkins, acrescentando Node 24 para as ações atuais. `run-local.py` regista o intérprete Python 3.13 existente na cache do act. Isso permite executar setup-python num container Debian sem pedir um binário preparado para Ubuntu.

### 4.2. Executar

```powershell
py -3 CA5/Alternative/run-local.py --branch development
py -3 CA5/Alternative/run-local.py --branch main
```

Executa as duas demonstrações uma de cada vez. O script copia os ficheiros versionáveis para uma árvore de trabalho isolada em `.local/`, cria um commit de teste e prepara um evento local da branch escolhida. A branch de trabalho do grupo não é alterada.

As variáveis da emulação apontam para o registo `localhost:15000`, o SSH encaminhado pelo Vagrant e o Mailpit. Só são fornecidos segredos gerados para o laboratório e a chave da VM local. Não se usa um token de escrita do GitHub nem se faz push para o GitHub ou Docker Hub.

Os artefactos de cada execução ficam numa pasta própria em `.local/actions-artifacts/`. Isso impede que execuções repetidas encontrem artefactos antigos com o mesmo nome. Os artefactos volumosos, incluindo o JAR, não são commitados; as evidências publicáveis contêm os relatórios, metadados e logs relevantes.

Foi encontrada corrupção de ZIPs grandes no servidor de artefactos local: o número de bytes guardados era inferior ao anunciado pelo upload e o download falhava. A emulação define `ACTIONS_ARTIFACT_UPLOAD_CONCURRENCY=1`, serializando os blocos enviados ao servidor local. Esta variável é fornecida pelo script do act, sem alterar o workflow no GitHub. A validação também compara o SHA-256 do JAR recuperado com o metadado do build.

O script limita os jobs do emulador para controlar os recursos. A matriz e os ficheiros de tempos permitem observar a execução dos testes sem assumir que o agendamento local será idêntico ao do serviço GitHub.

### 4.3. Validar uma falha

```powershell
py -3 CA5/Alternative/run-local.py --branch development --scenario unit-failure
```

Esta opção altera a expectativa de um teste unitário apenas na cópia isolada. A execução do workflow deve falhar, publicar os resultados de teste e enviar a notificação de falha, sem criar ou publicar uma imagem dessa versão e sem alterar a produção. O código do repositório principal mantém o teste correto. Um código de saída diferente de zero é esperado neste cenário.

### 4.4. Resultados e evidências

As execuções locais, os resultados JUnit, os metadados da imagem, o hash do JAR partilhado e as notificações recebidas são registados em `evidence/`. Os ficheiros `01-act-main.json` e `01-act-development.json` identificam explicitamente o fornecedor como `act-local-emulation`, incluindo commit de teste e run ID.

A emulação da main executou deploy e verificação por Ansible na VM. Na development, o estado da produção é comparado antes e depois da execução. A ausência de alteração do ID e da imagem constitui uma verificação adicional à condição do job.

| Evidência | Conteúdo |
|---|---|
| [01-act-main.txt](evidence/01-act-main.txt) | Workflow completo da main, incluindo deploy e verificação |
| [01-act-main.json](evidence/01-act-main.json) | Identidade e resultado da emulação main |
| [01-act-development.txt](evidence/01-act-development.txt) | Workflow development, com imagem publicada localmente e sem deploy |
| [01-act-development.json](evidence/01-act-development.json) | Resultado e comparação da produção antes/depois |
| [02-act-development-unit-failure.json](evidence/02-act-development-unit-failure.json) | Falha unitária deliberada, sem alteração da produção |
| [03-local-validation-summary.json](evidence/03-local-validation-summary.json) | JUnit, intervalos, integridade do JAR, imagem e e-mails |
| [04-final-local-checks.json](evidence/04-final-local-checks.json) | Sintaxe, ligações, ausência de segredos locais e aplicação UP |

Os ficheiros `-build.json` e `-push.json` guardam os metadados recuperados dos artefactos da própria execução. Os resultados do cenário de falha ficam em `02-act-development-unit-failure.*`.

Na main e na development passaram os três testes (um unitário e dois de integração). No cenário negativo falhou o teste unitário, os dois de integração passaram e os jobs de imagem e deploy foram bloqueados. A notificação FAILURE foi recebida e a produção manteve o mesmo container saudável. Os intervalos dos comandos sobrepuseram-se em 7,362 segundos na main e 3,945 segundos na development; estes valores demonstram concorrência local, sem constituir uma comparação de desempenho com o serviço GitHub.

Na primeira notificação negativa, o act devolveu uma expressão por avaliar como output do job de imagem ignorado. O envio foi ajustado para apresentar `não construída` quando esse job não termina com sucesso; uma nova chamada SMTP com o mesmo cenário confirmou o resultado corrigido. O log original foi preservado.

Para verificar os dados gravados, depois de executar os cenários:

```powershell
py -3 CA5/Alternative/collect-local-evidence.py --include-failure
```

## 5. Configuração posterior no GitHub

Esta fase fica para depois de terminares os testes locais e publicares o workflow.

### 5.1. Secrets

| Nome | Conteúdo |
|---|---|
| `DOCKERHUB_USERNAME` | Utilizador Docker Hub |
| `DOCKERHUB_TOKEN` | Access token com permissão para publicar a imagem |
| `CA5_PRODUCTION_SSH_KEY` | Chave privada completa da VM production |
| `SMTP_USERNAME` | Utilizador do servidor SMTP, quando há autenticação |
| `SMTP_PASSWORD` | Credencial SMTP, quando há autenticação |

### 5.2. Variables

| Nome | Valor ou finalidade |
|---|---|
| `CA5_IMAGE_REPOSITORY` | Por omissão, `luizbsilv/ca5-bookstore` |
| `CA5_REGISTRY_URL` | Por omissão, Docker Hub HTTPS |
| `CA5_PRODUCTION_HOST` | IP ou host SSH acessível a partir do runner |
| `CA5_PRODUCTION_SSH_PORT` | Porta SSH; por omissão, 22 |
| `SMTP_HOST`, `SMTP_PORT` | Servidor de envio de e-mail |
| `SMTP_STARTTLS`, `SMTP_SSL` | Modo TLS; por omissão STARTTLS e porta 587 |
| `NOTIFY_FROM`, `NOTIFY_TO` | Remetente autorizado e destinatário real |

Para SMTP com SSL direto, configura a porta adequada e `SMTP_SSL=true`. A implementação usa SSL direto quando esse modo é escolhido. O modo sem TLS usado pelo Mailpit é exclusivo da validação local.

### 5.3. Runner de produção

Regista um self-hosted runner Linux nas definições Actions do repositório e acrescenta a etiqueta `ca5-production`. Usa os comandos fornecidos pelo GitHub para a tua máquina, mantendo o token de registo fora dos ficheiros do trabalho.

Confirma que o runner consegue alcançar o SSH da VM. Se correr num container Docker Desktop, usa o encaminhamento do Vagrant e as variáveis de host/porta, como foi feito no laboratório. O workflow prepara Python 3.13 e Ansible Core 2.19.4; a compilação continua em Java 17 nos runners de build.

Antes de demonstrar o deploy desta alternativa, suspende o job de deploy Jenkins que utiliza a mesma VM. Depois de configurar secrets, variables e runner, faz pushes de teste na development e na main e guarda as evidências do serviço GitHub. Cria também a issue da alternativa nessa fase, mantendo as publicações remotas suspensas enquanto decorre a validação local.

## 6. Limitações e reflexão

| Aspeto | Cobertura e limite |
|---|---|
| Compilação, testes, artefactos, imagem e Ansible | Implementados no workflow e executados por act com serviços locais |
| Eventos GitHub reais | Definidos no YAML; só podem ser demonstrados após publicação |
| Checkout autenticado do repositório privado | O act copia a árvore local; não valida a autenticação do serviço GitHub |
| Artefactos do serviço GitHub | Validação local usa o servidor de artefactos do act; quotas e retenção do serviço não são exercitadas |
| Docker Hub no workflow | O mesmo script foi testado contra o registo local; a execução Actions contra Docker Hub fica para a publicação |
| Self-hosted runner registado | A etiqueta é emulada por um container local; o registo e a ligação ao GitHub ficam para a fase externa |
| E-mail externo | SMTP real exercitado contra Mailpit; entrega para um destinatário externo depende da configuração do servidor de envio |
| Estado UNSTABLE | Não existe equivalente direto no Actions; um teste falhado gera failure e bloqueia publicação/deploy |
| Persistência H2 | Mantém a limitação da solução base: dados em memória perdem-se ao substituir o container |
| Duas ferramentas sobre a mesma produção | Não há um bloqueio comum entre Jenkins e Actions; as demonstrações usam um responsável de deploy de cada vez |

A alternativa está implementada como workflow executável, não apenas desenhada. A emulação permite validar grande parte do percurso antes de publicar, mas não substitui a prova de uma execução alojada no GitHub. Essa distinção mantém os resultados locais separados dos requisitos que dependem da integração externa.

## 7. Referências

- [Sintaxe de workflows GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [Artefactos entre jobs](https://docs.github.com/en/actions/tutorials/store-and-share-data)
- [Runners próprios](https://docs.github.com/en/actions/reference/runners/self-hosted-runners)
- [Secrets](https://docs.github.com/en/actions/concepts/security/secrets)
- [setup-java](https://github.com/actions/setup-java)
- [setup-python](https://github.com/actions/setup-python)
- [act: execução local e artefactos](https://nektosact.com/usage/index.html)
- [actionlint](https://github.com/rhysd/actionlint)
- [Configuração da concorrência de upload no toolkit oficial](https://github.com/actions/toolkit/blob/main/packages/artifact/RELEASES.md)
- [Problema de corrupção de artefactos no act](https://github.com/nektos/act/issues/2351)
