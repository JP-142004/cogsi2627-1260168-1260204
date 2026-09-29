# Relatório Técnico — CA1, Parte 1: Introdução ao Gradle

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

A tag `v1.1.0` identifica a versão inicial importada da demonstração Gradle. A tag `ca1-part1` identifica o marco da Parte 1; deve apontar para o commit final que contém as correções e validações desta versão.