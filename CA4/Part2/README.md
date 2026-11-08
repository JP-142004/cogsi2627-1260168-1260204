# CA4 — Parte 2 · Bookstore com Docker Compose (proxy, web e db)

Este tutorial põe a Bookstore (versão Gradle do CA1) a correr em três containers, orquestrados com Docker Compose. É a mesma arquitetura do CA2 Parte 2, mas com containers em vez das três VMs do Vagrant:

```text
Windows / navegador
        |  http://localhost:8084
        v
proxy  — Nginx, porta interna 80
        |  http://web:8080
        v
web    — Bookstore Spring Boot, porta interna 8080
        |  jdbc:h2:tcp://db:9092/./bookstore
        v
db     — servidor H2 em modo TCP, porta interna 9092
        |
        v
volume h2-data — ficheiros da base de dados, fora do container
```

Só o proxy publica uma porta no Windows. O web e o db comunicam apenas pela rede interna do Compose, pelo nome do serviço.

Todos os comandos correm no PowerShell, a partir da pasta `CA4/Part2`, salvo indicação em contrário.

## 1. Pré-requisitos

- Docker Desktop com containers Linux (backend WSL 2) e o motor em execução ("Engine running").
- Git.
- Acesso à rede, para descarregar as imagens base, o H2 e as dependências Gradle.

```powershell
docker version
docker compose version
```

## 2. Organização da pasta

```text
CA4/Part2/
├── compose.yaml        # os três serviços, as redes e o volume
├── .env.example        # variáveis de exemplo (vai para o Git)
├── .gitignore          # ignora o .env pessoal e admite o .env.example
├── db/Dockerfile       # imagem do servidor H2
├── web/Dockerfile      # imagem da Bookstore (build multi-stage)
├── web/.dockerignore   # exclui builds e caches do contexto
├── web/app/            # código da Bookstore, copiado da Parte 1
├── proxy/Dockerfile    # imagem do Nginx
├── proxy/nginx.conf    # reencaminhamento para o web
└── evidence/           # saídas dos testes
```

O código da aplicação foi copiado de `CA4/Part1/source/CA1/week2`, sem a variante Maven. A cópia foi necessária porque o `DataInitializer` tinha de ser alterado (secção 6), e assim a Parte 1 continua reproduzível tal como foi entregue.

```powershell
# Na raiz do repositório
robocopy CA4\Part1\source\CA1\week2 CA4\Part2\web\app /E /XD maven-alternative
```

O `robocopy` devolve códigos de 0 a 7 quando a cópia corre bem.

## 3. Imagem do db (servidor H2)

`db/Dockerfile`:

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

- **Versão fixa do H2** (`2.2.224`), para o build ser reproduzível.
- **Utilizador `h2`** (não-root), dono da pasta `/data`, onde fica o volume.
- **`H2_PORT` e `H2_BASE_DIR`** têm valores por omissão no Dockerfile, e o Compose pode sobrepô-los. O `ENTRYPOINT` usa `sh -c` para o shell substituir as variáveis, e `exec` para o Java ficar como processo principal e receber os sinais de paragem.
- **`-tcpAllowOthers`** aceita ligações vindas de outros containers. **`-ifNotExists`** cria a base na primeira ligação.

## 4. Imagem do web (Bookstore)

`web/Dockerfile`, em duas fases:

```dockerfile
FROM eclipse-temurin:17-jdk AS build
WORKDIR /src
COPY app/ ./
RUN chmod +x gradlew && ./gradlew --no-daemon :app:bootJar -x test && cp $(ls app/build/libs/*.jar | grep -v plain) /src/app.jar

FROM eclipse-temurin:17-jre-alpine
RUN apk add --no-cache wget \
 && addgroup -S bookstore && adduser -S -G bookstore bookstore
WORKDIR /app
COPY --from=build /src/app.jar app.jar
USER bookstore
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

- **Java 17**, porque o `build.gradle` define `JavaLanguageVersion.of(17)` e a Parte 1 também usa 17.
- **Multi-stage**: o JDK e o Gradle ficam na primeira fase; a imagem final só tem o JRE e o JAR.
- **`:app:bootJar`**, porque o projeto Gradle tem o módulo `app`. O `grep -v plain` escolhe o JAR executável e não o `*-plain.jar`.
- **`wget`** é instalado para o healthcheck do Compose.
- **Utilizador `bookstore`** (não-root).

`web/.dockerignore`:

```text
app/build
app/.gradle
app/.idea
.git
```

Exclui do contexto os resultados de compilações feitas no Windows e as caches. Assim, o JAR é sempre compilado dentro do container e o contexto enviado ao Docker é mais pequeno. O proxy e o db não têm `.dockerignore`: os contextos deles só têm o Dockerfile e o `nginx.conf`.

## 5. Imagem do proxy (Nginx)

`proxy/Dockerfile`:

```dockerfile
FROM nginx:1.27-alpine
RUN rm -f /etc/nginx/conf.d/default.conf
COPY nginx.conf /etc/nginx/conf.d/bookstore.conf
EXPOSE 80
```

`proxy/nginx.conf`:

```nginx
server {
    listen 80;

    location / {
        proxy_pass http://web:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

No CA2, o proxy usava o IP da VM da aplicação. Aqui usa o nome `web`, que o DNS interno do Compose resolve. Dentro do container do proxy, `localhost` seria o próprio proxy, não a Bookstore.

## 6. Tornar a carga de dados idempotente

O `DataInitializer.java` original insere os livros, o cliente e a encomenda de exemplo **em cada arranque**. Com a base em memória da Parte 1 isso não se notava. Com a base persistente, cada reinício duplicava os dados.

Em `web/app/app/src/main/java/com/example/bookstore/config/DataInitializer.java`, no início do `CommandLineRunner`:

```java
return args -> {

    // Idempotente: so insere os dados de exemplo se a base estiver vazia
    if (bookRepo.count() > 0) {
        return;
    }

    // Books
    ...
```

Os dados existentes nunca são apagados: só se inserem os de exemplo quando a base está vazia.

## 7. Orquestrar com Docker Compose

`compose.yaml`:

```yaml
name: bookstore-ca4

services:
  db:
    build: ./db
    image: bookstore-db:ca4
    environment:
      H2_PORT: "9092"
      H2_BASE_DIR: /data
    volumes:
      - h2-data:/data
    networks:
      backend:
        ipv4_address: 172.28.0.30
    healthcheck:
      test: ["CMD-SHELL", "java -cp /opt/h2.jar org.h2.tools.Shell -url 'jdbc:h2:tcp://localhost:9092/./bookstore' -user sa -password '' -sql 'SELECT 1' | grep -q 1 || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 10s
    restart: unless-stopped

  web:
    build: ./web
    image: bookstore-web:ca4
    environment:
      SPRING_DATASOURCE_URL: jdbc:h2:tcp://db:9092/./bookstore
      SPRING_DATASOURCE_USERNAME: ${SPRING_DATASOURCE_USERNAME:-sa}
      SPRING_DATASOURCE_PASSWORD: ${SPRING_DATASOURCE_PASSWORD:-}
      SERVER_PORT: "8080"
    depends_on:
      db:
        condition: service_healthy
    networks:
      backend:
        ipv4_address: 172.28.0.10
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/actuator/health | grep -q '\"status\":\"UP\"' || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 20
      start_period: 20s
    restart: unless-stopped

  proxy:
    build: ./proxy
    image: bookstore-proxy:ca4
    ports:
      - "${PROXY_PORT:-8084}:80"
    depends_on:
      web:
        condition: service_healthy
    networks:
      - backend
      - frontend
    restart: unless-stopped

volumes:
  h2-data:

networks:
  backend:
    ipam:
      config:
        - subnet: 172.28.0.0/24
  frontend:
```

### Ordem de arranque e healthchecks

```text
db healthy → web arranca → web healthy → proxy arranca
```

Um `depends_on` simples só espera que o container **arranque**. Com `condition: service_healthy`, o Compose espera que o healthcheck do serviço anterior passe.

- **db**: o cliente do próprio H2 (`org.h2.tools.Shell`) liga-se por TCP à base persistente `./bookstore` e executa `SELECT 1`. Não basta a porta estar aberta: a base tem de responder. O caminho `./bookstore` é o mesmo do `SPRING_DATASOURCE_URL` do web, por isso o teste usa a mesma base que a aplicação.
- **web**: pede `/actuator/health` (o Actuator já vem no `build.gradle`) e só passa se a resposta tiver `"status":"UP"`. O `grep` faz o teste falhar se o endpoint responder com outro estado.

### Variáveis de ambiente

| Serviço | Variável | Para que serve |
| --- | --- | --- |
| db | `H2_PORT`, `H2_BASE_DIR` | Porta TCP e diretório de dados do H2 |
| web | `SPRING_DATASOURCE_URL` | Ligação TCP ao serviço `db`; sobrepõe o `jdbc:h2:mem:` do `application.properties` |
| web | `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD` | Credenciais da base, lidas do `.env` |
| web | `SERVER_PORT` | Porta interna da aplicação |
| proxy | `PROXY_PORT` | Porta publicada no Windows (8084 por omissão) |

`.env.example`:

```text
PROXY_PORT=8084
SPRING_DATASOURCE_USERNAME=sa
SPRING_DATASOURCE_PASSWORD=
```

`.gitignore` (da pasta `CA4/Part2`):

```text
.env
!.env.example
evidence/*.tmp
```

O `.env` pessoal fica fora do Git. O `.gitignore` da raiz ignora `.env.*`, por isso a linha `!.env.example` é necessária para versionar o ficheiro de exemplo.

### Rede e volume

- **`backend`** (172.28.0.0/24) liga os três serviços. Os IPs fixos (web 172.28.0.10, db 172.28.0.30) tornam as evidências previsíveis, mas a comunicação usa sempre os nomes.
- **`frontend`** só tem o proxy, que é o único serviço com porta publicada.
- **`h2-data`** é um volume nomeado montado em `/data` no db. Os ficheiros da base ficam fora do sistema de ficheiros do container, por isso sobrevivem quando os containers são removidos e recriados.

## 8. Construir e arrancar

```powershell
Copy-Item .env.example .env      # só na primeira vez
docker compose config --quiet    # valida o compose.yaml e o .env
docker compose up -d --build
docker compose ps
```

O primeiro build demora vários minutos, porque descarrega as imagens base e as dependências Gradle. Os seguintes reutilizam a cache.

Resultado observado:

```text
NAME                    IMAGE                 SERVICE   STATUS                    PORTS
bookstore-ca4-db-1      bookstore-db:ca4      db        Up 17 seconds (healthy)   9092/tcp
bookstore-ca4-proxy-1   bookstore-proxy:ca4   proxy     Up Less than a second     0.0.0.0:8084->80/tcp
bookstore-ca4-web-1     bookstore-web:ca4     web       Up 11 seconds (healthy)   8080/tcp
```

O proxy só aparece depois de o web estar `healthy`, como pretendido. Para ver o detalhe de cada healthcheck:

```powershell
docker inspect --format "{{json .State.Health}}" bookstore-ca4-db-1
docker inspect --format "{{json .State.Health}}" bookstore-ca4-web-1
```

No web, o primeiro registo pode ter `ExitCode 1` (a aplicação ainda estava a arrancar) e os seguintes `ExitCode 0`.

## 9. Testar a aplicação através do proxy

```powershell
curl.exe -i http://localhost:8084/books
curl.exe -s http://localhost:8084/actuator/health
```

Resultado observado:

```text
HTTP/1.1 200
Server: nginx/1.27.5
Content-Type: application/json

[{"id":1,"title":"Clean Code","author":"Robert C. Martin","price":30.0},{"id":2,"title":"Effective Java","author":"Joshua Bloch","price":40.0}]
```

```text
{"status":"UP"}
```

O cabeçalho `Server: nginx` confirma que o pedido passou pelo proxy.

## 10. Verificar a comunicação entre serviços

```powershell
docker compose exec proxy getent hosts web > evidence\connectivity-proxy-web.txt
docker compose exec web getent hosts db > evidence\connectivity-web-db.txt
```

Resultado observado:

```text
172.28.0.10       web  web
172.28.0.30       db  db
```

O proxy resolve `web` e a aplicação resolve `db`. A resolução de nomes, por si só, não prova que a aplicação funciona: isso é demonstrado pela resposta HTTP da secção 9 (proxy → web) e pelo healthcheck do web, que só fica `UP` com a ligação ao H2 a funcionar (web → db).

## 11. Demonstrar a persistência

Criar um livro diferente dos de exemplo, através do proxy:

```powershell
Invoke-RestMethod -Method Post -Uri http://localhost:8084/books -ContentType "application/json" -Body (@{title="Teste CA4"; author="Joao"; price=10.0} | ConvertTo-Json)
curl.exe -s http://localhost:8084/books > evidence\books-antes.json
```

No PowerShell, o `Invoke-RestMethod` é mais seguro que o `curl.exe` para enviar JSON: com o `curl.exe`, as aspas do corpo podem chegar deformadas e a API responde `400 Bad Request`.

Remover e recriar os containers, **mantendo o volume**:

```powershell
docker compose down
docker compose up -d
docker compose ps
curl.exe -s http://localhost:8084/books > evidence\books-depois.json
Get-Content evidence\books-antes.json -Raw
Get-Content evidence\books-depois.json -Raw
```

Resultado observado (igual nos dois ficheiros):

```text
[{"id":1,"title":"Clean Code","author":"Robert C. Martin","price":30.0},{"id":2,"title":"Effective Java","author":"Joshua Bloch","price":40.0},{"id":3,"title":"Teste CA4","author":"Joao","price":10.0}]
```

O livro de teste continua com o mesmo id, e os dados de exemplo não foram inseridos outra vez.

**Não usar `docker compose down -v` neste teste**: o `-v` apaga os volumes nomeados do projeto, e com eles os dados.

Para ver onde o Docker guarda o volume:

```powershell
docker volume inspect bookstore-ca4_h2-data > evidence\volume-h2-data.json
```

## 12. Observar recursos e camadas

```powershell
docker compose ps > evidence\compose-ps.txt
docker stats --no-stream > evidence\stats.txt
docker history bookstore-web:ca4 > evidence\history-web.txt
```

`docker stats` sem `--no-stream` atualiza CPU, memória, rede e I/O em tempo real (`Ctrl+C` para sair). `docker history` mostra que a imagem final do web só tem as camadas da base JRE, a instalação do `wget` e do utilizador e a cópia do JAR: a compilação ficou na fase de build.

## 13. Publicar as imagens no Docker Hub

As três imagens personalizadas foram publicadas na conta `joaopaulo14`, com a tag `v1`. As imagens base (`eclipse-temurin` e `nginx`) são oficiais e só foram reutilizadas, por isso não são publicadas.

```powershell
docker login
$conta = 'joaopaulo14'
foreach ($svc in 'db','web','proxy') {
    docker tag "bookstore-${svc}:ca4" "$conta/ca4-bookstore-${svc}:v1"
    docker push "$conta/ca4-bookstore-${svc}:v1"
}
```

- `docker tag` dá um segundo nome à imagem local, no formato `<conta>/<repositório>:<tag>`, que diz ao Docker para onde a enviar.
- `docker push` envia as camadas que o Docker Hub ainda não tem. Na segunda e na terceira imagem, várias camadas aparecem como `Mounted from joaopaulo14/ca4-bookstore-db`: são camadas partilhadas (a mesma base JRE do Temurin), que o Docker Hub reaproveita em vez de as receber outra vez.

Resultado observado:

| Imagem | Digest |
| --- | --- |
| [`joaopaulo14/ca4-bookstore-db:v1`](https://hub.docker.com/r/joaopaulo14/ca4-bookstore-db/tags) | `sha256:2b021c9cce3e85e4035d19daaef915172403fd902241ea73514a327f3a398f50` |
| [`joaopaulo14/ca4-bookstore-web:v1`](https://hub.docker.com/r/joaopaulo14/ca4-bookstore-web/tags) | `sha256:8fb2f62755d9828dc727ec33a9bf1cd77c2a021492bfcbb166b06f7902855811` |
| [`joaopaulo14/ca4-bookstore-proxy:v1`](https://hub.docker.com/r/joaopaulo14/ca4-bookstore-proxy/tags) | `sha256:73914a96d2233b659b8a7f4d1e90009b2309e919c4b54cb89de008e415428e0a` |

O digest identifica o conteúdo exato publicado: quem fizer `docker pull` com esse digest recebe exatamente estas imagens, mesmo que a tag `v1` venha a ser reutilizada.

Para usar as imagens publicadas noutro computador, sem compilar nada:

```powershell
foreach ($svc in 'db','web','proxy') {
    docker pull "joaopaulo14/ca4-bookstore-${svc}:v1"
    docker tag "joaopaulo14/ca4-bookstore-${svc}:v1" "bookstore-${svc}:ca4"
}
docker compose up -d --no-build
```

O `--no-build` faz o Compose usar as imagens já presentes (`bookstore-*:ca4`, os nomes indicados em `image:` no `compose.yaml`) em vez de as construir a partir dos Dockerfiles.

## 14. Parar a demonstração

```powershell
docker compose down        # remove containers e redes, mantém os dados
docker compose down -v     # remove também o volume (apaga a base)
```

## 15. Problemas encontrados e soluções

| Problema | Causa | Solução |
| --- | --- | --- |
| `COPY --from=build /src/build/libs` falhava | O módulo Gradle está em `/src/app/`, por isso o JAR fica em `app/build/libs` | `:app:bootJar` e cópia do JAR para `/src/app.jar` |
| Livros duplicados a cada arranque | O `DataInitializer` inseria sempre | Só insere se `bookRepo.count()` for 0 |
| `POST /books` com `curl.exe` devolvia 400 | O PowerShell deformava as aspas do JSON | `Invoke-RestMethod` com `ConvertTo-Json` |
| Imagens com Java 21 | O projeto está configurado para 17 | Bases `eclipse-temurin:17` no web e no db |
| `H2_DB_PATH` declarada mas sem efeito | O arranque não lia a variável | Substituída por `H2_BASE_DIR`, usada no `ENTRYPOINT` |
| Healthcheck do db só testava a porta | `nc -z` não prova que a base responde | `SELECT 1` com o cliente H2; `netcat` removido da imagem |
| Healthcheck do web pedia `/books` | Não usava o estado da aplicação | `/actuator/health` com `"status":"UP"` |
| `Dockerfile.v*` da Parte 1 dentro de `web/app` | Vieram na cópia do código | Removidos do Git |

## 16. Limitações

- **Credenciais do H2.** No modo servidor TCP com `-ifNotExists`, o utilizador e a palavra-passe da base são definidos pela primeira ligação, que é a do web (`SPRING_DATASOURCE_*`) ou a do healthcheck. O servidor não lê credenciais de variáveis, e o healthcheck usa `sa` sem palavra-passe, por isso alterar as credenciais no `.env` exige alinhar também o healthcheck.
- **Custo do healthcheck do db.** Cada verificação arranca uma JVM (a cada 5 segundos). É aceitável neste laboratório, mas numa instalação real seria preferível um cliente mais leve ou um intervalo maior.
- **Ordem de arranque.** O `service_healthy` organiza o arranque inicial. Se o db falhar mais tarde, a recuperação depende do `restart: unless-stopped` e da reconexão do Spring.
- **`application.properties`.** Continua com `jdbc:h2:mem:bookstore`; o Compose sobrepõe-no com `SPRING_DATASOURCE_URL`. Fora do Compose, a aplicação volta a usar a base em memória.

## Evidências

| Ficheiro | Conteúdo |
| --- | --- |
| `evidence/compose-ps.txt` | Estado dos três serviços, com os healthchecks |
| `evidence/connectivity-proxy-web.txt` | Resolução de `web` a partir do proxy |
| `evidence/connectivity-web-db.txt` | Resolução de `db` a partir do web |
| `evidence/books-antes.json`, `evidence/books-depois.json` | Lista de livros antes e depois de recriar os containers |
| `evidence/volume-h2-data.json` | `docker volume inspect` do volume da base |
| `evidence/stats.txt` | Amostra de CPU, memória, rede e I/O |
| `evidence/history-web.txt` | Camadas da imagem do web |
