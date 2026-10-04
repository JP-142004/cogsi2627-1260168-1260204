# Relatório Técnico — CA1: Gradle e alternativas

## Objetivo

A primeira parte da CA1 utiliza a aplicação de demonstração do Gradle fornecida pelo professor. O objetivo é explorar o projeto e o ciclo de build do Gradle, configurar tarefas para executar o servidor e criar um backup dos fontes, e adicionar um teste unitário.

O projeto está em `CA1/week1/build_tools/gradle_demo`.

## 1. Configuração inicial

A aplicação usa uma toolchain Java 17, mantendo a compatibilidade com a versão Java usada na CA0. A configuração encontra-se em `app/build.gradle`:

```groovy
java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}
```

O projeto também utiliza o Gradle Wrapper. A versão do Gradle está definida em `gradle/wrapper/gradle-wrapper.properties`; assim, os comandos são executados com a versão configurada para o projeto, sem exigir uma instalação global do Gradle.

## 2. Gradle Wrapper e JDK Toolchains

O Gradle Wrapper (`gradlew` e `gradlew.bat`) inicia a versão do Gradle indicada nos ficheiros do Wrapper. Se essa versão ainda não estiver disponível localmente, o Wrapper pode descarregá-la. Isso torna a versão do Gradle consistente entre os membros da equipa.

A toolchain Java define a versão do JDK usada pelas tarefas Java, como compilação, testes e execução. Neste projeto, a versão solicitada é Java 17. A configuração do resolver Foojay em `settings.gradle` permite ao Gradle descarregar uma toolchain compatível quando necessário.

Para consultar as instalações detetadas pelo Gradle, foi executado, a partir da pasta `gradle_demo`:

```powershell
.\gradlew.bat javaToolchains
```

A saída confirmou que a deteção automática e o descarregamento de toolchains estão ativos. O Gradle detetou:

- Eclipse Temurin JDK 17, provisionado automaticamente pelo Gradle;
- Microsoft JDK 17, detetado como a JVM atual;
- Oracle JDK 24, detetado pelo registo do Windows.

O relatório lista as instalações detetadas. Como o projeto pede Java 17, as tarefas Java necessitam de uma toolchain compatível com Java 17; o JDK 24 não corresponde a essa configuração.

## 3. Exploração das tarefas e dependências

A partir da pasta `gradle_demo`, os seguintes comandos permitem explorar as tarefas disponíveis e as dependências do subprojeto da aplicação:

```powershell
.\gradlew.bat :app:tasks --all
.\gradlew.bat :app:dependencies
```

O primeiro lista as tarefas Gradle disponíveis no subprojeto `app`. O segundo apresenta as configurações de dependências e respetivas dependências transitivas.

## 4. Tarefas personalizadas

### `runServer`

A tarefa `runServer`, do tipo `JavaExec`, inicia o servidor de chat pela classe `org.example.ChatServerApp`. Usa o `runtimeClasspath` da aplicação e aceita a propriedade `serverPort`; quando não é fornecida, utiliza a porta `59001`.

### `backupSources`

A tarefa `backupSources`, do tipo `Copy`, copia os fontes de produção e de teste para `app/build/backup`, preservando a estrutura `src/main` e `src/test`.

A tarefa `cleanBackup`, do tipo `Delete`, remove o backup anterior antes da nova cópia. Esta dependência evita que ficheiros antigos permaneçam no backup após alterações nos fontes.

### `archiveBackup`

A tarefa `archiveBackup`, do tipo `Zip`, depende de `backupSources` e cria o ficheiro `app/build/archives/sources-backup.zip`.

## 5. Teste unitário

Foi configurado o JUnit Jupiter através do catálogo de versões em `gradle/libs.versions.toml`. O teste `AppTest` verifica se a saudação devolvida por `App.getGreeting()` contém o nome da aplicação.

Para executar os testes, a partir da pasta `gradle_demo`, foi usado:

```powershell
.\gradlew.bat :app:test
```

A execução terminou com `BUILD SUCCESSFUL`. O relatório XML em `app/build/test-results/test/TEST-org.example.AppTest.xml` confirmou:

```text
tests="1"
failures="0"
errors="0"
```

## 6. Execução do servidor

O servidor foi iniciado com:

```powershell
.\gradlew.bat :app:runServer -PserverPort=59001
```

A aplicação apresentou a mensagem:

```text
The chat server is running...
```

O servidor manteve-se em execução à espera de ligações, como esperado. A execução foi terminada com `Ctrl+C`.

## 7. Criação e verificação do backup

O backup ZIP foi criado com:

```powershell
.\gradlew.bat :app:archiveBackup
```

A execução terminou com `BUILD SUCCESSFUL`. O conteúdo foi verificado com:

```powershell
tar -tf .\app\build\archives\sources-backup.zip
```

A listagem confirmou a presença de `src/main` e `src/test`, incluindo `src/test/java/org/example/AppTest.java`. A estrutura preservada permite distinguir os fontes da aplicação dos fontes de teste.

## 8. Referências das versões
A tag v1.1.0 identifica a versão inicial importada da demonstração Gradle. A tag ca1-part1 identifica o marco da Parte 1 e deve apontar para o commit final com as correções e validações desta versão.

## Parte 2 — Migração da Bookstore para Gradle

### Objetivo

O objetivo da segunda parte da CA1 foi migrar a aplicação Bookstore da CA0, originalmente baseada em Maven, para Gradle. A implementação inclui configuração de dependências, execução da aplicação, testes unitários e de integração, preparação de uma distribuição, implantação num diretório de desenvolvimento e geração de Javadoc.

Como alternativa tecnológica, foi implementada uma segunda versão da Bookstore com Maven. Isso permitiu comparar uma solução baseada em Gradle com outra ferramenta de automação de builds.

O projeto Gradle está em `CA1/week2`. A alternativa Maven está em `CA1/week2/maven-alternative`.

### 1. Análise e desenho da solução Gradle

A estrutura criada com `gradle init` usa um projeto raiz e o subprojeto `app`. Os fontes da Bookstore foram colocados em `app/src/main`, seguindo a estrutura convencional de projetos Java.

A configuração foi dividida entre:

- `settings.gradle`, que declara o nome do projeto e inclui `app`;
- `gradle/libs.versions.toml`, que centraliza as versões e coordenadas das dependências;
- `app/build.gradle`, que configura plugins, dependências, toolchain, testes e tarefas da aplicação.

Foi escolhida a toolchain Java 17 para manter a compatibilidade com a aplicação da CA0. As dependências Spring Boot estão declaradas no catálogo de versões, evitando espalhar coordenadas e versões pelo script de build.

### 2. Implementação e validação da migração Gradle

A aplicação usa Spring Web, Spring Data JPA, Spring HATEOAS, Actuator e H2. Foi executada com `bootRun`, e a página raiz respondeu com links para livros, clientes, encomendas, health e informação.

#### Teste unitário

O teste `ClientTest` verifica se o NIF atribuído a um cliente pode ser lido corretamente. Foi executado com:

```powershell
.\CA1\week2\gradlew.bat -p .\CA1\week2 :app:test
```

O relatório XML confirmou um teste, sem falhas nem erros.

#### Testes de integração

Foi criado um source set `integrationTest`, separado dos testes unitários. O teste `BookstoreApiIntegrationTest` inicia a aplicação numa porta aleatória e verifica a resposta HTTP da página raiz.

A tarefa `integrationTest` executa os testes de integração, e a tarefa `check` depende dela. A validação foi executada com:

```powershell
.\CA1\week2\gradlew.bat -p .\CA1\week2 :app:integrationTest
.\CA1\week2\gradlew.bat -p .\CA1\week2 build
```

O relatório XML da integração confirmou um teste, sem falhas nem erros. A tarefa `build` terminou com `BUILD SUCCESSFUL`.

#### Preparação do diretório de desenvolvimento

A tarefa `deployToDev` coordena a limpeza do diretório de implantação, a cópia do artefacto da aplicação, a cópia das dependências de runtime e a cópia do ficheiro de configuração. O filtro `ReplaceTokens` substitui propriedades como versão, ambiente e instante de build.

A tarefa foi executada com:

```powershell
.\CA1\week2\gradlew.bat -p .\CA1\week2 :app:deployToDev
```

A execução terminou com `BUILD SUCCESSFUL`, e os valores substituídos foram conferidos nos recursos processados.

#### Distribuição executável

A tarefa personalizada `runInstalledDist` depende de `installDist` e executa o script da distribuição gerado pelo Gradle para o sistema operativo. No Windows, o script fica em `app/build/install/app/bin/app.bat`.

O classpath do script gerado foi configurado para usar os JARs da pasta `lib` através de wildcard. Isso evita exceder o limite de comprimento da linha de comando do Windows. A distribuição iniciou a Bookstore com Java 17 e Spring Boot 3.3.0.

#### Javadoc

A tarefa personalizada `packageJavadoc` depende da geração de Javadoc e cria `app/build/archives/javadoc.zip`. O arquivo foi inspecionado e continha as páginas HTML das classes e dos pacotes.

### 3. Análise da solução alternativa: Maven

Maven foi escolhido como alternativa por ser uma ferramenta de automação de builds diferente de Gradle e já ser usado pela aplicação original da CA0. Assim, foi possível comparar duas ferramentas aplicadas à mesma aplicação e aos mesmos objetivos.

#### Automação do build e extensibilidade

Gradle organiza o build como um grafo de tarefas. Tarefas personalizadas podem declarar dependências, entradas e saídas e ser compostas para formar operações como `deployToDev`, `packageJavadoc` e `runInstalledDist`. O comportamento pode ser configurado em scripts Groovy e ampliado com plugins.

Maven organiza o build através de fases predefinidas do ciclo de vida, como `compile`, `test`, `package` e `verify`. Plugins associam objetivos a essas fases. Essa abordagem favorece convenções e uma sequência previsível; para operações específicas, como criar o ZIP do Javadoc ou adicionar uma pasta de testes de integração, é necessário configurar plugins no POM.

#### Desenho da alternativa para os mesmos objetivos

A solução Maven usa um `pom.xml` independente e o Maven Wrapper. As dependências Spring Boot são geridas pelo parent Spring Boot, e os plugins implementam os requisitos adicionais:

- Surefire executa os testes unitários;
- Build Helper adiciona `src/integrationTest/java` às fontes de teste;
- Failsafe executa os testes de integração durante `verify`;
- Maven Javadoc Plugin gera a documentação;
- Maven AntRun cria o ZIP da documentação;
- AppAssembler gera os scripts de execução e a distribuição com as dependências;
- Spring Boot Maven Plugin cria um JAR executável separado.

Este desenho permite mapear os objetivos do projeto Gradle para fases e plugins Maven, mantendo a separação entre código-fonte, testes unitários e testes de integração.

### 4. Implementação e validação da alternativa Maven

A alternativa está em `CA1/week2/maven-alternative`, com uma cópia dos fontes da Bookstore, um `pom.xml` próprio e o Maven Wrapper. O Wrapper permite executar a versão configurada do Maven sem depender de uma instalação global no `PATH`.

A validação foi executada com:

```powershell
.\CA1\week2\maven-alternative\mvnw.cmd `
    -f .\CA1\week2\maven-alternative\pom.xml `
    verify
```

A execução terminou com `BUILD SUCCESS`. Os relatórios confirmaram um teste unitário e um teste de integração, ambos sem falhas nem erros. Também foi criado `target/archives/javadoc.zip`.

O AppAssembler gerou os scripts `bookstore.bat` para Windows e `bookstore` para Unix, além de 78 JARs na distribuição. O script Windows iniciou a aplicação na porta 8081. A primeira tentativa na porta 8080 não conseguiu iniciar porque outra instância da aplicação já estava a usar essa porta.

### 5. Comparação e reflexão

| Aspeto | Gradle | Maven |
|---|---|---|
| Modelo de configuração | Scripts Groovy e catálogo de versões TOML | POM declarativo em XML |
| Organização do build | Grafo de tarefas e dependências entre tarefas | Fases do ciclo de vida com objetivos de plugins |
| Testes de integração | Source set e tarefa `integrationTest` configurados no build | Build Helper adiciona as fontes e Failsafe executa os testes |
| Distribuição | Application Plugin, `installDist` e tarefa personalizada | AppAssembler gera scripts e copia dependências |
| Javadoc em ZIP | Tarefa Gradle composta por geração e compactação | Maven Javadoc Plugin e AntRun |
| Extensão | Tarefas personalizadas e plugins Gradle | Objetivos de plugins associados às fases Maven |

Nesta aplicação, Gradle tornou direta a composição das tarefas próprias do trabalho e permitiu configurar as operações no mesmo script do build. Maven ofereceu um ciclo de vida convencional e plugins específicos para várias operações; a configuração ficou concentrada no POM, mas exigiu combinar plugins para cobrir todos os requisitos.

A alternativa Maven confirmou que os mesmos objetivos podem ser alcançados com outra ferramenta. Também evidenciou uma diferença de desenho: no Gradle, as operações foram expressas principalmente como tarefas; no Maven, como objetivos de plugins ligados às fases do ciclo de vida. A experiência com as duas soluções mostrou que a escolha depende do equilíbrio pretendido entre convenções estabelecidas, composição de tarefas e configuração explícita dos plugins.

### 6. Autoavaliação da contribuição


| Membro | Contribuição |
|---|---:|
| João Paulo Arantes Martins | 50% |
| Luiz Afonso Barbosa Silva  | 50% |
| **Total** | **100%** |

### 7. Conclusão

A Bookstore foi migrada para Gradle e validada com execução da aplicação, testes unitários, testes de integração, distribuição executável, preparação de um diretório de desenvolvimento e geração de Javadoc.

A implementação Maven reproduziu esses objetivos principais e permitiu comparar o modelo de tarefas do Gradle com o ciclo de vida e os plugins do Maven. Os diretórios `build` e `target` contêm artefactos locais gerados durante as validações e estão excluídos do Git.