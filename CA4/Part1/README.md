# CA4 — Parte 1: contentorização do Chat e da Bookstore

## Objetivo e organização

Executar os servidores das duas aplicações do CA1 em containers e aceder-lhes a partir do host. O trabalho encontra-se no ramo `ca4-part1`; os ficheiros específicos desta parte ficam nesta pasta. As aplicações foram copiadas para `source/CA1`, preservando os exercícios anteriores. A Bookstore usa a versão Gradle; a pasta histórica `maven-alternative` não participa na construção v3.

| Aplicação | Contexto de construção | Porta do servidor |
| --- | --- | --- |
| Chat | `source/CA1/week1/build_tools/gradle_demo` | 59001 |
| Bookstore | `source/CA1/week2` | 8080 |

## Análise e desenho

Cada aplicação tem três Dockerfiles, permitindo comparar estratégias sem alterar o código Java.

| Versão | Origem e compilação | Conteúdo da imagem final |
| --- | --- | --- |
| v1 | `git clone` durante o build e compilação no JDK | JDK, Git, código, histórico Git e cache Gradle |
| v2 | Compilação e testes no Windows; cópia dos artefactos | JRE e aplicação com dependências de execução |
| v3 | Compilação no primeiro estágio; cópia dos artefactos para o segundo | JRE e aplicação com dependências de execução; utilizador `app` |

O Chat produz um JAR fino e uma pasta `lib` com Log4j, pelo que o arranque usa `java -cp`. A Bookstore produz um JAR executável Spring Boot com `bootJar`, iniciado com `java -jar`. O Java 17 corresponde às toolchains das aplicações.

### Clone da versão 1 sem credenciais

Como o repositório do grupo é privado e não se pretende publicar alterações nesta fase, o script cria `source.bundle` com `git bundle create`, a partir do ramo local. O Dockerfile executa efetivamente `git clone` desse bundle durante a construção. Não copia uma pasta `.git` do host e não recebe tokens ou palavras-passe.

Esta é uma adaptação local do requisito de clone: a origem é um arquivo Git, não uma ligação ao GitHub. O bundle inclui o histórico alcançável do ramo, incluindo outros trabalhos do repositório. Na v1 isso aumenta a exposição de código e mantém ficheiros de desenvolvimento na imagem, pelo que esta versão é apenas didática. Os bundles são ignorados pelo Git e pelas construções v2/v3. Antes de qualquer publicação da v1, deve preparar-se uma origem que contenha apenas o código que se pretende distribuir. O script regista o commit usado em `evidence/images.json`.

As cópias locais do Chat e da Bookstore correspondem ao código original de `CA1` usado pela v1. Se forem feitas alterações funcionais nas cópias, o caminho clonado da v1 deverá ser atualizado para a cópia em `CA4/Part1/source`, para manter as três versões comparáveis.

## Pré-requisitos

- Windows, PowerShell 7, Git e Docker Desktop com containers Linux em execução.
- JDK 17 disponível em `JAVA_HOME` ou no `PATH`.
- Acesso à rede para descarregar imagens base, Gradle, pacotes Git e dependências Maven.
- Python 3 para a verificação automatizada; o script usa apenas a biblioteca padrão.

## Construção reproduzível

Na raiz do repositório, com o ramo selecionado e os ficheiros guardados:

```powershell
./CA4/Part1/Build-Images.ps1 -NoCache
```

O script cria os bundles locais, executa `clean`, `test` e a tarefa de empacotamento de cada aplicação no host, constrói as seis imagens, mede os tempos, inspeciona as camadas e guarda os resultados em `evidence`. Interrompe a execução se qualquer comando falhar. Os caches Gradle do host ficam em `.cache`, fora do controlo de versões.

Para executar uma construção individual, entrar no contexto da aplicação:

```powershell
# Gerar primeiro os bundles e artefactos com o script acima.
docker build -f Dockerfile.v1 --build-arg SOURCE_REF=ca4-part1 -t ca4-chat:v1 .
docker build -f Dockerfile.v2 -t ca4-chat:v2 .
docker build -f Dockerfile.v3 -t ca4-chat:v3 .
```

Na pasta da Bookstore, usar os mesmos comandos com as tags `ca4-bookstore:v1`, `v2` e `v3`.

### Justificação dos ficheiros de exclusão

Cada Dockerfile tem um `<Dockerfile>.dockerignore` próprio:

- **v1:** exclui tudo e admite apenas o bundle e o Dockerfile. O código é obtido por clone, não por cópia da árvore local.
- **v2:** admite apenas o diretório dos JARs do Chat ou o JAR executável exato da Bookstore. O compilador e os fontes ficam fora do contexto.
- **v3:** exclui `.gradle`, `build`, `.git` e o bundle. Assim, o build não consegue reutilizar JARs compilados no host. Na Bookstore também se exclui a alternativa Maven.

## Executar e ligar os clientes no host

```powershell
docker run -d --name ca4-chat-demo -p 127.0.0.1:59003:59001 ca4-chat:v3
docker run -d --name ca4-bookstore-demo -p 127.0.0.1:8083:8080 ca4-bookstore:v3
```

A publicação das portas em `127.0.0.1` permite o acesso local. `EXPOSE` documenta a porta interna; é `-p` que publica a porta no host. As portas 59003/8083 evitam interferir com o Chat v2 que já estava em execução na porta 59001.

No contexto do Chat, abrir dois terminais e executar em cada um:

```powershell
./gradlew.bat :app:runClient -PserverIP=localhost -PserverPort=59003
```

Escolher nomes diferentes e enviar mensagens nos dois sentidos. O cliente gráfico permanece no Windows e o servidor corre no container. Para a Bookstore:

```powershell
Invoke-RestMethod http://localhost:8083/actuator/health
Invoke-RestMethod http://localhost:8083/books
```

A base H2 desta parte está em memória: os dados desaparecem quando o processo termina. A persistência e a separação de serviços pertencem à Parte 2.

Para terminar apenas os containers desta demonstração:

```powershell
docker stop ca4-chat-demo ca4-bookstore-demo
docker rm ca4-chat-demo ca4-bookstore-demo
```

### Verificação automatizada

```powershell
python ./CA4/Part1/Verify-Images.py
./CA4/Part1/Summarize-Results.ps1
```

O script cria containers temporários com portas locais atribuídas automaticamente, verifica as seis imagens e remove apenas esses containers. No Chat, dois clientes TCP no host cumprem o protocolo de registo e confirmam a entrega de mensagens nos dois sentidos. Na Bookstore, o host consulta o estado, lista livros, cria um livro e volta a lê-lo. Também verifica o UID e a presença de Git e do compilador. Este teste valida o protocolo real sem abrir janelas Swing; a utilização gráfica manual tem os comandos acima.

Os resultados ficam em `evidence/verification.json`; os logs de arranque, em `*-runtime.txt`. Os testes unitários do host constam de `*-host-build.txt`. As verificações HTTP/TCP complementam os testes unitários existentes.

## Comparação e interpretação das medições

Consultar [os resultados medidos](evidence/RESULTS.md), [os dados das imagens](evidence/images.json) e [a verificação funcional](evidence/verification.json).

O tempo da v2 tem duas parcelas: compilação/testes no host e construção da imagem. Comparar apenas `docker build` favorece artificialmente a v2. A v3 compila em ambiente controlado e tende a aproximar-se do tamanho final da v2, embora acrescente uma camada para criar o utilizador. A v1 conserva JDK, Git, código e cache, aumentando tamanho e superfície de ataque.

Foi usada uma medição por imagem com `--no-cache`, por ordem v1, v2 e v3. As imagens base já podiam estar presentes; o cache de rede e do sistema operativo não foi limpo. O tempo da compilação no host inclui testes, enquanto os builds v1/v3 executam apenas o empacotamento. Os tempos são observações deste computador, não um benchmark estatístico nem uma comparação perfeitamente isolada. O tamanho é `docker image inspect .Size`; não é o tamanho comprimido do registo nem o espaço exclusivo ocupado em disco. O número de camadas é a contagem de `RootFS.Layers`, não o número de linhas de `docker history`.

### Histórico das camadas

```powershell
docker history --no-trunc ca4-chat:v1
docker history --no-trunc ca4-chat:v2
docker history --no-trunc ca4-chat:v3
docker history --no-trunc ca4-bookstore:v3
```

Os históricos das seis imagens estão em `evidence/*-history.txt`. A v1 mostra instalação de Git, cópia do bundle, clone e compilação. A v2 contém essencialmente as camadas da base e a cópia dos artefactos. No histórico final da v3, as instruções de compilação do primeiro estágio não aparecem como camadas herdadas: só o resultado é copiado. Instruções de metadados como `USER`, `EXPOSE` e `ENTRYPOINT` podem aparecer com tamanho zero e não criar camadas de sistema de ficheiros.

### Segurança

As versões v3 criam um utilizador de sistema `app` e usam `USER app`. O processo Java deixa de ter UID 0, reduzindo os privilégios disponíveis se a aplicação for comprometida e restringindo alterações em ficheiros protegidos do container. Isto contribui para o princípio do menor privilégio e reduz riscos, mas não elimina falhas de isolamento ou vulnerabilidades das dependências. Não foram atribuídas capacidades adicionais nem montadas pastas do host. As versões v1/v2 mantêm o utilizador da imagem base para tornar a comparação explícita.

Git e `javac` são necessários no build v1, mas não na execução. As verificações confirmam a sua ausência nas imagens v2/v3. A redução de ferramentas e ficheiros diminui a superfície exposta; não equivale a uma análise de vulnerabilidades. As bases usam tags mutáveis; os digests efetivamente usados constam dos logs. Para uma entrega congelada, deve fixar-se o digest escolhido.

## Monitorização de recursos

Com os containers de demonstração ativos:

```powershell
docker stats ca4-chat-demo ca4-bookstore-demo
```

Enquanto o comando atualiza CPU, memória, rede e I/O de blocos, trocar mensagens e fazer pedidos HTTP noutro terminal. `Ctrl+C` termina apenas a visualização. O limite de memória apresentado não é o consumo atual. Para uma amostra única:

```powershell
docker stats --no-stream ca4-chat-demo ca4-bookstore-demo
```

A verificação automática guarda amostras reais em `verification.json`, depois da atividade dos clientes. São observações pontuais, não máximos de carga. O `docker stats` em tempo real já tinha sido experimentado no Chat v2 antes desta continuação; a recolha automática permite reproduzir e registar a observação para as seis imagens.

## Solução alternativa: análise e desenho com Podman

Podman permite reutilizar os Dockerfiles e oferece execução sem um daemon central permanente no Linux. No Windows necessita de uma máquina Linux gerida por `podman machine`. A execução rootless e `USER app` atuam em níveis diferentes: a primeira reduz os privilégios do motor/utilizador no host Linux; a segunda define o utilizador do processo na imagem.

O desenho mantém as três estratégias por aplicação, portas publicadas para clientes locais e inspeção de recursos. Para v3, a construção pode usar explicitamente o ficheiro de exclusão correspondente:

```powershell
podman machine init
podman machine start
# Executar no contexto do Chat:
podman build --ignorefile Dockerfile.v3.dockerignore -f Dockerfile.v3 -t localhost/ca4-chat:v3 .
podman run -d --name ca4-chat-podman -p 127.0.0.1:59004:59001 localhost/ca4-chat:v3
podman stats --no-stream ca4-chat-podman
podman history localhost/ca4-chat:v3
```

Na Bookstore, o equivalente usa a tag `localhost/ca4-bookstore:v3` e `8084:8080`. Os clientes e testes HTTP/TCP continuam no host, apontando para essas portas. Para v1/v2, reutilizam-se os bundles ou artefactos preparados no host e seleciona-se o respetivo `--ignorefile`. A alternativa permite comparar os mesmos artefactos, mas deve ser medida separadamente: diferenças de VM, armazenamento e rede alteram os resultados.

Fontes: [construção com Podman](https://docs.podman.io/en/stable/markdown/podman-build.1.html) e [Podman no Windows](https://github.com/podman-container-tools/podman/blob/main/docs/tutorials/podman-for-windows.md).

### Estado da implementação alternativa

O desenho e os comandos estão documentados. Podman não está instalado neste ambiente, pelo que a alternativa **não foi executada nem validada**. Não se reivindica o requisito adicional de implementação da alternativa para a classificação máxima. Não foi instalada uma segunda plataforma de containers nesta continuação.

## Entrega e pendências explícitas

- Construção, comparação, inspeção e testes locais: consultar as evidências.
- Publicação no Docker Hub: pendente; nenhuma imagem foi publicada nesta continuação. A v1 contém o histórico privado e requer preparação de uma origem apropriada antes de ser distribuída.
- Issues e envio ao GitHub: não realizados, conforme a instrução de manter o trabalho local.
- Tag `ca4-part1`: reservar para o fecho da entrega, após resolver a publicação e rever as pendências; o ramo já tem esse nome.
- Autoavaliação: Luiz Afonso — percentagem a confirmar pelo grupo; João — percentagem a confirmar pelo grupo. Os valores devem representar o trabalho efetivo de cada membro e não foram inventados.
- Parte 2: não desenvolvida nesta continuação.

Depois de preparar a publicação, os comandos de referência para cada imagem são `docker tag ca4-chat:v3 <utilizador>/ca4-chat:v3` e `docker push <utilizador>/ca4-chat:v3`, repetindo para as outras versões e para a Bookstore. Estes comandos estão apenas documentados, não foram executados.


---

# Parte 2 — Docker Compose com proxy, web e db (João)

## Objetivo

Executar a Bookstore (versão Gradle do CA1) em três containers, orquestrados com Docker Compose, em vez das três máquinas Vagrant do CA2 Parte 2:

- **proxy**: Nginx, ponto de entrada HTTP, publicado no host na porta 8084.
- **web**: Bookstore Spring Boot, na porta interna 8080.
- **db**: servidor H2 em modo TCP, na porta interna 9092, com os dados num volume Docker.

Os ficheiros desta parte estão em `CA4/Part2/`, e o código vem de `CA4/Part1/source/CA1/week2`, copiado para `CA4/Part2/web/app/` sem a variante Maven.

## Análise e desenho

**Ordem de arranque.** O `web` só inicia quando o `db` está `healthy`, e o `proxy` só inicia quando o `web` está `healthy`. Usa-se `depends_on` com `condition: service_healthy`, porque `depends_on` sem condição só espera que o container arranque, não que o serviço esteja pronto.

**Healthchecks.**
- `db`: abre uma ligação TCP ao H2 e executa `SELECT 1` com o cliente do próprio H2 (`org.h2.tools.Shell`). O teste usa a base persistente, não uma base em memória. Cada verificação arranca uma JVM (intervalo de 5 s), um custo aceitável para o laboratório.
- `web`: pede `/actuator/health` e confirma `"status":"UP"`.

**Persistência.** O volume nomeado `h2-data` está montado em `/data` no db. O H2 usa `-baseDir ${H2_BASE_DIR}`, e a base `./bookstore` fica em `/data`. Um `docker compose down` (sem `-v`) preserva os dados.

**Rede.** Os serviços encontram-se pelo nome (`web`, `db`), e os IPs fixos da rede `backend` (172.28.0.0/24) tornam as evidências previsíveis: `web` em 172.28.0.10 e `db` em 172.28.0.30.

**Justificações.**
- **Java 17** em todas as imagens, porque o `build.gradle` define `JavaLanguageVersion.of(17)` e a Parte 1 também usa 17.
- **Utilizadores não-root** no web (`bookstore`) e no db (`h2`), para reduzir privilégios dentro do container.
- **Variáveis de ambiente.** O `.env` (não versionado) define `PROXY_PORT` e as credenciais do datasource. O `.env.example` mostra os valores, e o `.gitignore` ignora `.env` mas permite `.env.example`.
- **`DataInitializer` idempotente.** Antes, cada arranque inseria os livros de exemplo de novo, e com o volume persistente os dados duplicavam. Agora só insere se a tabela de livros estiver vazia.

## Passo a passo

### 1. Ramo e estrutura

```powershell
git switch main
git pull --ff-only origin main
git switch -c ca4-part2
mkdir CA4\Part2\web\app, CA4\Part2\db, CA4\Part2\proxy, CA4\Part2\evidence
```

### 2. Código da Bookstore

```powershell
robocopy CA4\Part1\source\CA1\week2 CA4\Part2\web\app /E /XD maven-alternative
```

O `robocopy` devolve códigos 0 a 7 em caso de sucesso.

### 3. Imagem do db (H2)

`db/Dockerfile`: base `eclipse-temurin:17-jre-alpine`, H2 `2.2.224` (versão fixa), utilizador `h2` e pasta `/data`. O servidor arranca em TCP na porta 9092, com o diretório base definido por `H2_BASE_DIR`.

```dockerfile
FROM eclipse-temurin:17-jre-alpine

ARG H2_VERSION=2.2.224
RUN apk add --no-cache wget \
 && wget -qO /opt/h2.jar https://repo1.maven.org/maven2/com/h2database/h2/${H2_VERSION}/h2-${H2_VERSION}.jar \
 && addgroup -S h2 && adduser -S -G h2 h2 \
 && mkdir -p /data && chown h2:h2 /data

ENV H2_PORT=9092 H2_BASE_DIR=/data
USER h2
VOLUME ["/data"]
EXPOSE 9092
ENTRYPOINT ["sh", "-c", "exec java -cp /opt/h2.jar org.h2.tools.Server -tcp -tcpPort ${H2_PORT} -tcpAllowOthers -ifNotExists -baseDir ${H2_BASE_DIR}"]
```

### 4. Imagem do web (Bookstore)

`web/Dockerfile` em duas fases: a primeira (`eclipse-temurin:17-jdk`) compila com `./gradlew :app:bootJar -x test` e copia o JAR sem o sufixo `plain`; a segunda (`eclipse-temurin:17-jre-alpine`) traz só o JRE e o JAR, com utilizador `bookstore`.

`web/.dockerignore`, para não enviar caches e builds para o contexto:

```
app/build
app/.gradle
app/.idea
.git
```

### 5. Imagem do proxy (Nginx)

`proxy/Dockerfile`: base `nginx:1.27-alpine`, sem a configuração por defeito. `proxy/nginx.conf` faz `proxy_pass http://web:8080` com os cabeçalhos `X-Real-IP`, `X-Forwarded-For` e `X-Forwarded-Proto`.

### 6. Compose

`compose.yaml`, com os três serviços, a rede `backend` e o volume `h2-data`, os healthchecks e as dependências descritas acima. A porta do proxy vem de `PROXY_PORT` (padrão 8084).

```powershell
cd CA4\Part2
Copy-Item .env.example .env
docker compose config --quiet
```

### 7. Correção do `DataInitializer`

No início do `CommandLineRunner` (`config/DataInitializer.java`):

```java
if (bookRepo.count() > 0) {
    return;
}
```

### 8. Subir e testar

```powershell
docker compose down -v
docker compose up -d --build
docker compose ps
curl.exe -s http://localhost:8084/books
```

Resultado: `db` e `web` em `healthy`, com a lista dos dois livros de exemplo (ids 1 e 2).

### 9. Persistência

```powershell
Invoke-RestMethod -Method Post -Uri http://localhost:8084/books -ContentType "application/json" -Body (@{title="Teste CA4"; author="Joao"; price=10.0} | ConvertTo-Json)
curl.exe -s http://localhost:8084/books > evidence\books-antes.json
docker compose down
docker compose up -d
curl.exe -s http://localhost:8084/books > evidence\books-depois.json
```

Resultado: os dois ficheiros têm os mesmos três livros (os de exemplo e o "Teste CA4", id 3), sem duplicados. Não usar `down -v` neste teste, porque apaga o volume.

### 10. Conectividade, volume e recursos

```powershell
docker compose exec proxy getent hosts web > evidence\connectivity-proxy-web.txt
docker compose exec web getent hosts db > evidence\connectivity-web-db.txt
docker volume inspect bookstore-ca4_h2-data > evidence\volume-h2-data.json
docker compose ps > evidence\compose-ps.txt
docker stats --no-stream > evidence\stats.txt
docker history bookstore-web:ca4 > evidence\history-web.txt
```

Resultado: o proxy resolve `web` para `172.28.0.10` e o web resolve `db` para `172.28.0.30`.

## Problemas encontrados

| Problema | Solução |
| --- | --- |
| Caminho do JAR errado no build | `:app:bootJar` e cópia do JAR de `app/build/libs/` |
| Livros duplicados a cada arranque | Guarda `count() > 0` no `DataInitializer` |
| Imagens com Java 21 | Alinhadas para Java 17 |
| `H2_DB_PATH` sem efeito | Renomeada para `H2_BASE_DIR`, usada no `ENTRYPOINT` |
| Healthcheck do db só testava a porta | `SELECT 1` com o cliente H2 |
| Ficheiros `Dockerfile.v*` copiados por engano para `web/app/` | Removidos do Git |

## Limitações

- As credenciais do H2 são definidas pela primeira ligação feita pelo web, não pelo servidor.
- O healthcheck do db arranca uma JVM a cada verificação.
- Só o web tem `.dockerignore`; proxy e db não copiam código de compilação.
- O `application.properties` continua com `jdbc:h2:mem:bookstore`, mas o Compose sobrepõe-no com `SPRING_DATASOURCE_URL`.

## Autoavaliação (João)

__% (a confirmar pelo grupo)