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

# Parte 2 — Migração da Bookstore para Gradle
Objetivo
Na Semana 2, migrámos a aplicação Bookstore da CA0 para um projeto Gradle com Spring Boot. Também configurámos testes unitários e de integração, tarefas de empacotamento e uma implementação alternativa com Maven para comparar as ferramentas de build.
O projeto Gradle está em CA1/week2; a alternativa Maven está em CA1/week2/maven-alternative.

## 1. Projeto Gradle e dependências
O projeto usa o Gradle Wrapper para executar a versão configurada do Gradle. A aplicação usa Java 17 e as dependências Spring Boot estão declaradas no catálogo gradle/libs.versions.toml.
A aplicação Bookstore da CA0 foi copiada para app/src/main. A configuração em app/build.gradle inclui Spring Web, Spring Data JPA, Spring HATEOAS, Actuator e H2. A aplicação pode ser iniciada com bootRun.
A página raiz respondeu com links para livros, clientes, encomendas, health e informação. Ao tentar iniciar uma segunda instância na porta 8080, a aplicação indicou que a porta já estava ocupada; a instância alternativa foi posteriormente testada na porta 8081.

## 2. Teste unitário
O teste ClientTest verifica o armazenamento e a leitura do NIF de um cliente. Foi executado com:
.\CA1\week2\gradlew.bat -p .\CA1\week2 :app:test
O relatório XML indicou um teste, sem falhas nem erros.

## 3. Testes de integração
Foi criado um source set integrationTest, separado dos testes unitários. O teste BookstoreApiIntegrationTest inicia a aplicação numa porta aleatória e verifica a resposta HTTP da página raiz.
A tarefa integrationTest executa os testes de integração, e a tarefa check também depende dela. Validámos com:
.\CA1\week2\gradlew.bat -p .\CA1\week2 :app:integrationTest
.\CA1\week2\gradlew.bat -p .\CA1\week2 build
O relatório XML indicou um teste de integração, sem falhas nem erros, e a tarefa build terminou com BUILD SUCCESSFUL.

## 4. Distribuição Gradle
A tarefa personalizada runInstalledDist depende de installDist e executa o script gerado pelo Gradle para o sistema operativo. No Windows, o script é app/build/install/app/bin/app.bat.
O classpath do script foi ajustado para usar os JARs da pasta lib com wildcard, evitando o limite de comprimento de comando do Windows. A execução da distribuição iniciou a Bookstore com Java 17 e Spring Boot 3.3.0. A aplicação foi encerrada com Ctrl+C.

## 5. Empacotamento de configuração para desenvolvimento
As propriedades service.version, service.environment e service.buildTimestamp são filtradas durante o processamento dos recursos. A tarefa deployToDev prepara o artefacto, as dependências de runtime e o ficheiro de configuração no diretório app/build/deployment/dev.
A substituição das propriedades foi verificada em app/build/resources/main/application.properties. A tarefa foi executada com:
.\CA1\week2\gradlew.bat -p .\CA1\week2 :app:deployToDev
A execução terminou com BUILD SUCCESSFUL.

## 6. Documentação Javadoc
A tarefa personalizada packageJavadoc gera a documentação Javadoc e cria app/build/archives/javadoc.zip. O arquivo ZIP foi inspecionado e continha páginas HTML das classes e dos pacotes.

## 7. Solução alternativa com Maven
Para comparar ferramentas de build, foi criado CA1/week2/maven-alternative, com uma cópia dos fontes da Bookstore e um pom.xml independente. O Maven Wrapper permite executar a versão configurada do Maven sem depender do comando mvn no PATH.
O POM configura Java 17, dependências Spring Boot, testes unitários, testes de integração com Build Helper e Failsafe, geração de Javadoc em ZIP e scripts de distribuição com AppAssembler. O plugin Spring Boot gera também um JAR executável separado.
A alternativa foi validada com:
.\CA1\week2\maven-alternative\mvnw.cmd `
    -f .\CA1\week2\maven-alternative\pom.xml `
    verify
A compilação terminou com BUILD SUCCESS. Os relatórios mostraram um teste unitário e um teste de integração, ambos sem falhas nem erros. O arquivo target/archives/javadoc.zip foi criado. O AppAssembler gerou os scripts bookstore.bat e bookstore, além de 78 JARs na distribuição.
O script bookstore.bat iniciou a aplicação na porta 8081. A primeira tentativa na porta 8080 falhou porque outra instância já estava a usar essa porta.

## 8. Comparação entre Gradle e Maven
Aspeto	Gradle	Maven
Configuração	Scripts Groovy e catálogo versionado de dependências	POM declarativo em XML
Execução	Gradle Wrapper e tarefas configuráveis	Maven Wrapper e ciclo de vida por fases
Testes	Tarefas test e integrationTest	Surefire para testes unitários e Failsafe para testes de integração
Distribuição	Application Plugin, installDist e script personalizado	AppAssembler gera scripts e diretório com dependências
Javadoc	Tarefa Gradle personalizada que cria ZIP	Maven Javadoc Plugin e AntRun criam ZIP


As duas ferramentas conseguiram compilar, testar, documentar e preparar uma distribuição executável da mesma aplicação. Gradle organiza o processo através de tarefas e dependências entre tarefas. Maven organiza-o através de fases do ciclo de vida e plugins configurados no POM.

## 9. Conclusão
A migração permitiu executar a Bookstore com Gradle, validar a aplicação com testes unitários e de integração, preparar uma distribuição e gerar documentação Javadoc.
A implementação Maven reproduziu os objetivos principais e serviu de base para comparar os modelos de configuração e extensão das duas ferramentas.
Os artefactos gerados nas pastas build e target são resultados locais de build e estão excluídos do Git.
```