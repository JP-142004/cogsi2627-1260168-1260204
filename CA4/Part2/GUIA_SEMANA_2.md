# Guia para o João — CA4, Semana 2

Este guia organiza o que desenvolver, em que ordem trabalhar e como demonstrar que funciona. É um roteiro: os ficheiros de implementação e os resultados desta parte ainda precisam de ser produzidos e testados.

## 1. O objetivo, explicado de forma simples

Na Semana 1, o servidor da Bookstore foi colocado num container. Na Semana 2, queremos separar o sistema em três containers e iniciar tudo com Docker Compose:

```text
Cliente no Windows / navegador
            |
            | http://localhost:8084
            v
      proxy — Nginx, porta interna 80
            |
            | http://web:8080
            v
      web — Bookstore Spring Boot
            |
            | ligação H2 TCP para db:9092
            v
      db — servidor H2
            |
            v
      volume Docker — ficheiro persistente do banco
```

O proxy recebe o pedido, encaminha-o para a aplicação e devolve a resposta. A aplicação consulta o servidor H2. O volume guarda o ficheiro do banco fora do sistema de ficheiros descartável do container.

É semelhante ao CA2 Parte 2, mas usando containers e Compose em vez das três máquinas Vagrant. O Chat não faz parte desta segunda semana.

## 2. O que já existe e pode ser aproveitado

Todos os caminhos desta secção são relativos à raiz do repositório.

| Material existente | Onde procurar | Para que serve |
| --- | --- | --- |
| Bookstore em Gradle | `CA4/Part1/source/CA1/week2` | Código da aplicação |
| Dockerfile multi-stage da Bookstore | `CA4/Part1/source/CA1/week2/Dockerfile.v3` | Base para construir o serviço web |
| Relatório da Semana 1 | `CA4/Part1/README.md` | Explica build e execução da aplicação |
| Resultados da Semana 1 | `CA4/Part1/evidence/RESULTS.md` | Evidências das imagens já testadas |
| Servidor H2 do CA2 | `CA2/Part2/provisioning/setup_db.sh` | Referência para arranque do H2 TCP |
| Proxy do CA2 | `CA2/Part2/provisioning/setup_proxy.sh` | Referência da configuração Nginx |

Na Semana 1, as três versões de cada aplicação foram construídas e passaram nos testes locais. A imagem da Bookstore v3 já usa um utilizador sem privilégios de root.

Os commits da Semana 1 estão publicados no GitHub. A tag `ca4-part1` identifica a versão usada na publicação das imagens.

## 3. Preparar o ramo e a pasta

Confirmar Docker Desktop com containers Linux, Docker Compose e Git disponíveis:

```powershell
docker version
docker compose version
git status
```

Depois de receber a Semana 1 e com a árvore de trabalho limpa, criar o ramo a partir dela, na raiz do repositório:

```powershell
git switch ca4-part1
git switch -c ca4-part2
```

Se o ramo `ca4-part2` já existir, continuar nesse ramo em vez de tentar criá-lo novamente. Não descartar alterações locais para trocar de ramo.

Manter os ficheiros específicos em `CA4/Part2`. Uma organização possível é:

```text
CA4/Part2/
├── GUIA_SEMANA_2.md          # este roteiro
├── compose.yaml            # os três serviços, rede e volume
├── .env.example            # variáveis de exemplo, sem credenciais reais
├── .gitignore              # ignorar .env e admitir .env.example
├── web/                    # Dockerfile e eventuais scripts do serviço web
├── db/                     # Dockerfile e arranque do H2
├── proxy/                  # Dockerfile e configuração/template do Nginx
├── evidence/               # saídas dos testes e imagens relevantes
└── README.md               # relatório da implementação efetivamente realizada
```

Pode reutilizar o contexto da aplicação em `../Part1/source/CA1/week2`, configurando os caminhos de build no Compose. Se precisar alterar o código Java, é preferível criar uma cópia própria da aplicação em Part2 para manter a demonstração da Semana 1 reproduzível. Não copiar caches, builds ou pastas `.git`.

## 4. Primeiro implementar o serviço db

Preparar uma imagem com Java para executar o H2 em modo servidor TCP, na porta interna 9092. Usar uma versão do H2 compatível com a dependência da Bookstore; confirmar a versão resolvida pelo Gradle, em vez de escolher uma versão arbitrária.

O script do CA2 mostra o uso de `org.h2.tools.Server`, incluindo opções de TCP, porta e diretório de dados. Adaptar o arranque para container: executar o processo em primeiro plano, sem systemd ou Vagrant.

Montar um volume nomeado numa pasta de dados, por exemplo `/data`. O ficheiro do banco precisa de ser criado dentro dessa pasta, e o utilizador do processo precisa de poder escrever nela.

Configurar por variáveis o nome do banco, credenciais e diretório de dados. Atenção: o H2 não passa a utilizar uma variável só porque ela foi declarada no Compose. O script de arranque/inicialização deve aplicar esses valores, incluindo a criação do banco e do utilizador quando necessário. A mesma configuração deve ser usada pelo web e pelo healthcheck.

Preparar um healthcheck que consiga confirmar uma ligação ao banco, preferencialmente executando uma consulta simples como `SELECT 1` com o cliente H2. As ferramentas usadas no teste devem existir na imagem. Não usar uma base em memória no healthcheck para concluir que o banco persistente está pronto.

Resultado desta etapa: o H2 arranca, aceita uma ligação TCP válida e fica healthy. A porta do banco pode permanecer apenas na rede interna do Compose.

## 5. Depois implementar o serviço web

Reutilizar o processo multi-stage da Semana 1: compilar com JDK 17 e executar o JAR Spring Boot numa imagem final com JRE 17. Manter a execução sem root e disponibilizar uma ferramenta adequada ao healthcheck.

O ficheiro atual `app/src/main/resources/application.properties` contém:

```properties
spring.datasource.url=jdbc:h2:mem:bookstore
```

Essa configuração cria um banco em memória dentro do processo da aplicação. Para a Semana 2, o serviço web deve receber uma ligação TCP ao serviço db. Um exemplo de URL é:

```text
jdbc:h2:tcp://db:9092/./bookstore
```

O caminho deve corresponder ao diretório base e ao nome configurados no servidor H2. Neste exemplo, `db` é o nome do serviço Compose; a resolução de nomes substitui os IPs fixos usados no CA2.

Usar variáveis Spring Boot como:

| Variável | Finalidade |
| --- | --- |
| `SPRING_DATASOURCE_URL` | URL TCP do H2 |
| `SPRING_DATASOURCE_USERNAME` | Utilizador do banco |
| `SPRING_DATASOURCE_PASSWORD` | Palavra-passe correspondente |
| `SPRING_JPA_HIBERNATE_DDL_AUTO` | Para este laboratório, `update` evita recriar as tabelas a cada arranque |
| `SERVER_PORT` | Porta interna da aplicação, por exemplo 8080 |

Configurar o healthcheck do web para consultar `/actuator/health`. A aplicação já inclui Actuator. Verificar se o comando realmente falha quando o endpoint não responde ou indica falha; não assumir que uma ferramenta como curl está instalada na imagem base.

No Compose, o web deve depender do db com `condition: service_healthy`. Só colocar `depends_on: db` não garante que o banco esteja pronto para receber ligações.

Resultado desta etapa: a aplicação liga ao H2 externo e fica healthy.

## 6. Preparar o serviço proxy

Usar Nginx para receber os pedidos HTTP e encaminhá-los para `http://web:8080`, ou para a porta interna parametrizada escolhida.

No CA2, o proxy usava um IP de máquina virtual. Aqui deve usar o nome `web`, reconhecido na rede Compose. Dentro de um container, `localhost` aponta para esse próprio container: no proxy, `localhost:8080` não aponta para a Bookstore.

Publicar a porta do proxy no Windows, por exemplo `8084:80`, e tornar a porta externa configurável. Os serviços web e db não precisam de portas publicadas no host para comunicar entre si.

Se usar um template Nginx para parametrizar o destino, garantir que o arranque gera a configuração final; declarar uma variável no Compose não substitui automaticamente texto num ficheiro Nginx qualquer.

Configurar o proxy para depender do web healthy. A ordem pretendida é:

```text
db healthy → web inicia → web healthy → proxy inicia
```

Essa ordem organiza o arranque inicial. Não representa, por si só, recuperação automática de todas as falhas posteriores; a aplicação também precisa de tolerar e recuperar ligações ao banco.

Resultado desta etapa: um pedido a `http://localhost:8084/books` atravessa o proxy e chega à Bookstore.

## 7. Centralizar as configurações

Criar `.env.example` com valores de exemplo para os três serviços. Sugestões de nomes:

```text
PROXY_PORT
WEB_PORT
DB_PORT
DB_NAME
DB_USER
DB_PASSWORD
DB_DATA_DIR
DOCKERHUB_USER
IMAGE_TAG
```

No Compose, mapear esses valores para as propriedades que cada serviço realmente usa. O `.env` fornece valores para substituição no Compose; variáveis que a aplicação precisa de ler também devem ser passadas ao container por `environment` ou `env_file`.

O ficheiro `.env` pessoal fica fora do Git. Há um detalhe neste repositório: o `.gitignore` da raiz já ignora `.env.*`. Acrescentar uma exceção adequada para permitir versionar `.env.example`, por exemplo `!.env.example` num `.gitignore` em Part2. Confirmar com `git check-ignore -v .env.example` e com o estado do Git.

Resultado desta etapa: alterar a porta externa ou as credenciais de teste não exige editar vários ficheiros manualmente.

## 8. Construir e testar os três serviços

Quando os ficheiros estiverem implementados, executar dentro de `CA4/Part2`:

```powershell
Copy-Item .env.example .env
# Preencher os valores locais antes de continuar.
docker compose config --quiet
docker compose up -d --build
docker compose ps
docker compose logs --tail 100 db web proxy
```

Criar o `.env` apenas se ainda não existir, para não substituir uma configuração pessoal. A porta dos exemplos seguintes é 8084; adaptar se `PROXY_PORT` tiver outro valor.

```powershell
Invoke-RestMethod http://localhost:8084/actuator/health
Invoke-RestMethod http://localhost:8084/books
```

Confirmar a comunicação pelo nome dos serviços: proxy alcança `web`; web alcança `db`. Podem ser usados comandos de resolução de nomes dentro dos containers se as imagens os incluírem. Guardar também evidências de pedidos que efetivamente atravessam essas ligações; resolver um nome sozinho não demonstra que a aplicação funciona.

Guardar as saídas de `docker compose ps`, os estados dos healthchecks e exemplos de respostas HTTP.

## 9. Demonstrar a persistência

Criar um livro diferente dos dados de exemplo, através do proxy:

```powershell
$payload = @{
    title = 'Livro de teste da Semana 2'
    author = 'Grupo COGSI'
    price = 15.0
} | ConvertTo-Json

$createdBook = Invoke-RestMethod -Method Post `
    -Uri http://localhost:8084/books `
    -ContentType 'application/json' -Body $payload

$bookId = $createdBook.id
Invoke-RestMethod "http://localhost:8084/books/$bookId"
```

Anotar o ID, parar e remover os containers preservando o volume e voltar a iniciar:

```powershell
docker compose down
docker compose up -d
# Aguardar a aplicação ficar disponível.
Invoke-RestMethod "http://localhost:8084/books/$bookId"
```

O mesmo livro deve continuar disponível com o mesmo ID. Guardar a resposta antes e depois, a identificação do volume e o respetivo ponto de montagem no serviço db.

Para este teste, não usar `docker compose down -v`: essa opção remove os volumes nomeados geridos pelo projeto e elimina os dados que queremos preservar.

Há um detalhe real no código atual: `DataInitializer.java` insere os livros, cliente e encomenda de exemplo em cada arranque. Com armazenamento persistente, isso pode duplicar os dados iniciais. Tornar essa inicialização idempotente na cópia da Semana 2, por exemplo inserindo dados de exemplo apenas quando apropriado para uma base vazia, sem apagar registros existentes.

Resultado desta etapa: recriar os containers não perde o livro de teste nem volta a inserir desnecessariamente os dados iniciais.

## 10. Escrever o relatório enquanto se trabalha

O `CA4/Part2/README.md` deve permitir a outra pessoa reproduzir a implementação. Incluir:

- Objetivo e desenho com proxy, web e db.
- O que foi reutilizado da Semana 1 e adaptado do CA2.
- Função dos Dockerfiles, ficheiros de exclusão e configuração Compose.
- Variáveis e procedimento de configuração local.
- Healthchecks e ordem de arranque.
- Rede, nomes dos serviços e portas internas/externas.
- Volume e demonstração da persistência.
- Comandos de construção, execução, consulta de logs e paragem.
- Evidências de HTTP, conectividade, readiness e recuperação dos dados.
- Problemas encontrados, soluções aplicadas e limitações reais.

O enunciado pede um README associado ao CA4. Coordenar também um `CA4/README.md` que reúna ou encaminhe claramente para os relatórios das duas partes e apresente a autoavaliação acordada pelos membros. Este guia não substitui o relatório dos resultados executados.

## 11. Commits e publicação

Fazer commits pequenos no ramo da Semana 2, com mensagens naturais em português. Exemplos, a usar apenas quando o trabalho correspondente estiver pronto:

```text
Adiciona o servidor H2 com armazenamento persistente
Liga a Bookstore ao banco externo
Configura o proxy e a ordem de arranque dos serviços
Regista os testes de persistência e o relatório da segunda parte
```

O enunciado pede publicação das imagens no Docker Hub. Preparar tags com o utilizador do grupo e uma versão identificável, associando `image:` aos serviços construídos para que o Compose possa publicá-los. Distinguir imagens personalizadas de imagens oficiais apenas reutilizadas.

A publicação é uma etapa posterior a combinar com o Luiz. As imagens da Semana 1 ainda não foram publicadas, e a v1 dessa parte contém histórico privado. Não a distribuir como está. Nenhum comando de publicação foi executado ao criar este guia.

Depois de validar a entrega e resolver as publicações, marcar o commit final com a tag Git `ca4-part2`. O envio de commits/tags ao GitHub continua dependente da combinação do grupo.

## 12. Alternativa tecnológica e fecho

O CA4 também pede análise e desenho de alternativa à ferramenta de contentorização; implementar uma alternativa é o requisito adicional para a classificação máxima. O [relatório do CA4](../README.md) documenta o desenho com Podman para as duas partes e os testes propostos. Coordenar essa parte com o Luiz: decidir como cobrir a solução com três serviços e quais limitações apresentar. Não declarar a alternativa como validada sem a executar.

### Lista final de verificação

- [ ] Ramo próprio da Semana 2 e commits incrementais.
- [ ] Três serviços chamados `proxy`, `web` e `db` no Compose.
- [ ] Bookstore Gradle construída de forma reproduzível.
- [ ] H2 externo em TCP, com dados num volume nomeado.
- [ ] Web espera pelo db healthy; proxy espera pelo web healthy.
- [ ] Healthchecks executáveis nas imagens escolhidas.
- [ ] Comunicação por nomes dos serviços demonstrada.
- [ ] HTTP funciona através do proxy.
- [ ] Configuração dos três serviços feita por variáveis aplicadas efetivamente.
- [ ] Livro criado permanece após remover e recriar os containers.
- [ ] Dados iniciais não são duplicados a cada arranque.
- [ ] README e evidências correspondem ao que foi realmente executado.
- [ ] Análise/desenho da alternativa coordenados; implementação identificada como feita ou pendente.
- [ ] Publicação no Docker Hub resolvida com o grupo.
- [ ] Autoavaliação acordada, sem inventar percentagens.
- [ ] Tag final `ca4-part2` criada no commit de entrega.

## Referências

- Requisitos CA4: consultar especialmente os slides da Parte 2 e da solução alternativa no enunciado fornecido pelo docente.
- [Docker Compose: ordem de arranque e service_healthy](https://docs.docker.com/compose/how-tos/startup-order/).
- [Docker Compose: variáveis dentro dos containers](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/).
- [Docker Compose: substituição de variáveis e .env](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/).

Estado deste documento: guia de passagem de trabalho, criado em 3 de novembro de 2026. A implementação da Semana 2 não foi executada durante a preparação deste roteiro.
