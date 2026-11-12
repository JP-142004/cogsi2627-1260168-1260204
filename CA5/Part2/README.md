# CA5 — Parte 2 · Imagem Docker e deploy em produção

Neste tutorial vais criar um pipeline Jenkins que compila a Bookstore, executa os testes unitários e de integração em paralelo, constrói uma imagem Docker e publica-a no Docker Hub. Na branch `main`, o pipeline vai implantar essa imagem numa VM de produção criada com Vagrant, usando Ansible, e verificar a saúde da aplicação.

O trabalho decorre na branch `ca5-part2` e está associado à [issue #21](https://github.com/JP-142004/cogsi2627-1260168-1260204/issues/21). A base é a Parte 1, integrada na `main` pelo commit `f020c07`. A alternativa ao Jenkins será desenvolvida separadamente com GitHub Actions.

## 1. Estado da implementação

Este README acompanha a implementação. Só os passos identificados como validados têm evidências de execução; as etapas pendentes descrevem trabalho a realizar.

| Bloco | Estado |
|---|---|
| Branch e issue da Parte 2 | Criadas |
| Bookstore, compilação e testes | Validados: 1 teste unitário e 2 de integração |
| Dockerfile com Java 17, utilizador sem privilégios e health check | Validado: imagem construída, container `healthy`, API HTTP 200 e UID/GID 10001 |
| VM de produção e Ansible | Pendentes |
| Jenkins Multibranch e testes em paralelo | Pendentes |
| Publicação no Docker Hub e deploy exclusivo na `main` | Pendentes |
| Disparo automático, notificações e demonstração final | Pendentes |
| Alternativa GitHub Actions | Planeada; implementação ainda não iniciada |

## 2. Arquitetura prevista

```text
Push na main/development
          |
          v
Jenkins Multibranch
  checkout -> assemble -> testes unitários + integração em paralelo
          -> imagem Docker -> arquivo de metadados -> Docker Hub
                                                        |
                                            só na main  v
                                                     Ansible
                                                        |
                                                        v
                                         VM de produção / Docker
                                         Bookstore + H2 em memória
                                         GET /actuator/health
```

Os testes têm de passar antes da publicação e do deploy. A imagem terá uma tag que inclui a origem do pipeline, a branch, o número da execução e o commit. O deploy receberá essa tag concreta, em vez de depender de `latest`.

## 3. Preparar a aplicação

Vais trabalhar a partir da raiz do repositório. A pasta `bookstore/` é uma cópia dos ficheiros versionados de `CA5/Part1/bookstore`; não inclui `.git`, caches nem artefactos de compilação. Manténs o Gradle Wrapper 8.8 e a toolchain Java 17 da Parte 1.

No Windows, entra na pasta e confirma o Java:

```powershell
cd CA5/Part2/bookstore
java -version
.\gradlew.bat clean assemble test integrationTest --no-daemon --console=plain
```

Em Linux, usa o mesmo wrapper:

```bash
cd CA5/Part2/bookstore
./gradlew clean assemble test integrationTest --no-daemon --console=plain
```

Neste primeiro teste local executas as tarefas numa só chamada. O paralelismo exigido pelo enunciado será configurado e demonstrado no Jenkins, usando pastas de trabalho isoladas.

O `assemble` produz dois JARs em `app/build/libs/`:

- `app-1.0.0.jar`: JAR executável Spring Boot, usado na imagem.
- `app-1.0.0-plain.jar`: JAR sem as dependências necessárias ao arranque autónomo; não é copiado para a imagem.

Os testes estão separados em `app/src/test` e `app/src/integrationTest`. Além do teste ao endpoint raiz herdado da Parte 1, o teste de integração verifica que `/actuator/health` responde HTTP 200 com `status: UP`. Os relatórios XML ficam em `app/build/test-results/test/` e `app/build/test-results/integrationTest/`.

Podes consultar a execução inicial em [01-gradle-build-tests.txt](evidence/01-gradle-build-tests.txt).

## 4. Construir e testar a imagem Docker

O Docker tem de estar a correr com containers Linux. A partir de `CA5/Part2/bookstore`, constrói a imagem depois de gerar o JAR:

```powershell
docker build --tag cogsi-ca5-bookstore:local .
docker run --detach --name cogsi-ca5-part2-local --publish 127.0.0.1:18085:8080 cogsi-ca5-bookstore:local
```

A porta 18085 do host é usada apenas para o teste local, evitando ocupar a porta 8080 que poderá ser usada pelo Jenkins. Na VM de produção, a aplicação usará a porta 8080.

Consulta o estado do container e a resposta HTTP:

```powershell
docker inspect --format '{{.State.Health.Status}}' cogsi-ca5-part2-local
curl.exe --fail http://127.0.0.1:18085/actuator/health
curl.exe --fail http://127.0.0.1:18085/
docker exec cogsi-ca5-part2-local id
```

Aguarda até o estado ser `healthy`. O resultado esperado do endpoint é `{"status":"UP"}` e o utilizador do processo deve ter UID e GID 10001. O `HEALTHCHECK` tem um período inicial de 90 segundos e tolera o arranque mais lento em VMs.

Quando terminares o teste, remove apenas este container:

```powershell
docker rm --force cogsi-ca5-part2-local
```

Na validação local, a imagem foi construída com sucesso, o container ficou `healthy`, ambos os pedidos HTTP responderam com sucesso e o processo correu com UID/GID 10001. O container foi removido no fim. Podes consultar a [construção](evidence/02-docker-build.txt) e o [teste de execução](evidence/03-docker-runtime.txt).

### Justificação do Dockerfile

Usas `eclipse-temurin:17-jre-jammy` porque a compilação já pertence ao stage Assemble. A imagem precisa apenas do runtime Java 17 e do JAR executável. Instalas `curl` para o health check e crias um utilizador de sistema sem privilégios.

O `.dockerignore` permite apenas o JAR executável no contexto enviado ao Docker. Assim, o código-fonte, os testes, caches e o JAR plain ficam fora desse contexto.

A base de dados H2 é mantida em memória, dentro do mesmo container da aplicação. Ao substituir o container, perdes os dados dessa instância; esta solução não oferece persistência de dados entre deploys.

## 5. Próximos blocos

Vais criar uma VM de produção com Vagrant, inicialmente em `192.168.56.20`, e validar o SSH. Depois vais implementar o playbook que instala Docker, autentica no Docker Hub, obtém a imagem pela tag, substitui o container e aguarda pelo health check.

O Jenkinsfile ficará em `CA5/Part2/Jenkinsfile`. Configurarás um job Multibranch para usar esse caminho, reconhecer `main` e `development` e executar o deploy apenas na `main`. Antes da demonstração final, ambas as branches terão de conter este Jenkinsfile.

As credenciais do GitHub, Docker Hub, SSH e notificações ficam no Jenkins Credentials. Não as guardes nos ficheiros, nas evidências ou no histórico Git.

## 6. Ambiente e problemas encontrados

Na preparação de 12 de novembro de 2026 foram confirmados Java 17, Gradle Wrapper 8.8, Docker Desktop com engine Linux, Vagrant 2.4.9 e VirtualBox 7.2.18. A box `ubuntu/jammy64` versão `20241002.0.0` já está disponível localmente.

O Docker Desktop estava parado e foi iniciado antes da construção da imagem. O WSL tinha apenas a distribuição interna `docker-desktop`; é necessário preparar uma distribuição Ubuntu para o Jenkins e o Ansible antes de executar o pipeline completo no ambiente previsto.

A integração GitHub permitiu consultar issues, mas devolveu HTTP 403 ao tentar criar uma. A issue #21 foi criada com o GitHub CLI, usando a sessão já autenticada do utilizador.

## 7. Evidências

| Ficheiro | Conteúdo |
|---|---|
| [01-gradle-build-tests.txt](evidence/01-gradle-build-tests.txt) | Compilação, teste unitário e testes de integração |
| [02-docker-build.txt](evidence/02-docker-build.txt) | Construção da imagem Docker local |
| [03-docker-runtime.txt](evidence/03-docker-runtime.txt) | Container saudável, API HTTP 200 e utilizador sem privilégios |

As evidências de execução no Jenkins, publicação e produção serão acrescentadas quando esses blocos forem validados.

## 8. Referências

- Enunciado CA5, páginas 13–18: requisitos da Parte 2 e da alternativa; o PDF é fornecido pela disciplina e não está incluído no repositório.
- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/): `COPY`, `USER` e `HEALTHCHECK`.
- [Jenkins Multibranch Pipeline](https://www.jenkins.io/doc/book/pipeline/multibranch/): descoberta de branches e identificação da branch em execução.
- [GitHub Actions: artefactos entre jobs](https://docs.github.com/en/actions/tutorials/store-and-share-data): base para o desenho da alternativa.
