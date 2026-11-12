# CA5 — Pipelines CI/CD

Neste trabalho vais automatizar a compilação, os testes e o deploy da aplicação Bookstore com Jenkins e analisar uma alternativa com GitHub Actions. A primeira parte implanta o JAR numa VM green; a segunda constrói uma imagem Docker e implanta-a numa VM de produção.

| Parte | Conteúdo | Relatório |
|---|---|---|
| Parte 1 | Jenkins, Vagrant, Ansible, blue/green, artefactos estáveis e rollback | [Tutorial da Parte 1](Part1/README.md) |
| Parte 2 | Jenkins Multibranch, testes paralelos, imagem Docker, rastreabilidade e deploy só na main | [Tutorial da Parte 2](Part2/README.md) |
| Alternativa | Análise, desenho e implementação equivalente com GitHub Actions | [Análise e implementação](Alternative/README.md) |

## 1. Análise, desenho e implementação das partes

Na Parte 1, duas VMs representam os ambientes blue e green. O pipeline constrói e testa a aplicação, arquiva versões estáveis e implanta na green quando o parâmetro DEPLOY está ativo. O playbook de rollback recupera uma versão arquivada e volta a verificar a saúde da aplicação. A conclusão está identificada pela tag `ca5-part1`.

Na Parte 2, a aplicação e o H2 correm no mesmo container. A infraestrutura é uma VM Vagrant provisionada por Ansible. O Jenkins Multibranch obtém o commit da branch correta, compila com Java 17, executa testes unitários e de integração em paralelo, constrói uma imagem com tag única, arquiva Dockerfile e metadados e publica a imagem. Só a main pode executar o deploy, seguido de verificação automática e notificação do resultado.

A [documentação do laboratório local](Part2/jenkins/README.md) permite reproduzir os testes sem publicar alterações no GitHub. Usa um repositório Git de teste, registo de imagens autenticado e caixa SMTP locais. Foram observados SUCCESS, UNSTABLE e FAILURE, com bloqueio da publicação de versões inválidas e preservação da produção nos cenários da development.

## 2. Análise da solução alternativa

O GitHub Actions foi escolhido por integrar os eventos do repositório e permitir jobs com dependências, matriz de testes, artefactos e secrets. A comparação com Jenkins cobre execução por branch, paralelismo, manutenção, agentes/runners, publicação de resultados, rastreabilidade e gestão de credenciais.

A principal restrição da infraestrutura é o acesso à VM local: os jobs de compilação podem usar runners hospedados, mas o deploy precisa de um self-hosted runner com conectividade ao laboratório. A análise e os compromissos estão desenvolvidos na [secção de comparação da alternativa](Alternative/README.md#1-análise-e-comparação).

## 3. Implementação da alternativa

O workflow está em [`.github/workflows/ca5-bookstore.yml`](../.github/workflows/ca5-bookstore.yml). Reutiliza os scripts, Dockerfile e playbooks da Parte 2 e implementa compilação, matriz de testes, artefactos, publicação, condição de deploy e SMTP. Foi preparada uma execução local com act e validação por actionlint, antes da publicação no GitHub.

O relatório da alternativa identifica explicitamente as diferenças de estados, resultados JUnit, disponibilidade do runner e requisitos que só podem ser demonstrados na integração externa. Uma emulação local não é apresentada como uma execução alojada no GitHub.

## 4. Estado da entrega

| Elemento | Estado |
|---|---|
| Parte 1 e tag `ca5-part1` | Integradas na main |
| Parte 2 — aplicação, Docker, VM e Ansible | Implementados e validados |
| Parte 2 — Jenkins Multibranch | Validado localmente e contra a branch real do GitHub, com publicação Docker Hub |
| Alternativa GitHub Actions | Validada por act e executada no GitHub na ca5-part2: compilação, testes, artefactos e Docker Hub passaram; e-mail pendente |
| Publicação das novas alterações no GitHub | Autorizada exclusivamente na branch `ca5-part2`; main sem alterações |
| Prova dos eventos GitHub e execução externa final | Push na ca5-part2 demonstrado; main e deploy externo ficam para depois da integração |
| SMTP para destinatário externo | Parâmetros Microsoft 365 definidos; autorização de envio pendente; captura local validada |
| Tag final `ca5-part2` | A criar depois da revisão e validação externas |

## 5. Autoavaliação e contribuição

Percentagens acordadas pelo grupo:

| Membro | Contribuição | Trabalho principal |
|---|---:|---|
| João Paulo Arantes Martins | 50% | Parte 1: infraestrutura blue/green, pipeline Jenkins, rollback e documentação |
| Luiz Afonso | 50% | Parte 2: Docker, produção, Ansible, Multibranch, testes e notificações; alternativa e documentação |

Cada relatório inclui passos reproduzíveis, justificações, problemas encontrados e evidências. Os segredos não fazem parte dos ficheiros versionados.
