# Relatório Técnico - CA1 (Parte 1: Iniciação ao Gradle)

Nesta primeira parte do trabalho prático de COGSI, o objetivo foi pegar na aplicação de demonstração do Gradle fornecida pelo professor (localizada na pasta do projeto) e prepará-la, ajustá-la e documentá-la para garantir a correta build e execução.

---

## 1. Configuração Inicial e Ajuste da Versão do Java

Como no projeto anterior (CA0) tínhamos definido o ambiente a correr com o **Java 17**, ao analisar o `build.gradle` original da demo do professor verificámos que a toolchain vinha configurada para o Java 21.

Para evitar conflitos locais e manter a consistência com o que já tínhamos configurado na máquina, ajustámos o bloco da toolchain no ficheiro `build.gradle` para a versão 17:

```groovy
java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}
```

---

## 2. Explicação dos Mecanismos do Gradle

Para defender o repositório perante o professor, é fundamental justificar o uso das ferramentas base:

* **Gradle Wrapper (`gradlew` / `gradlew.bat`):** 
  Utilizamos o wrapper para garantir que o projeto compila e executa exatamente com a mesma versão do Gradle em qualquer máquina, eliminando a necessidade de instalar o Gradle manualmente no sistema operativo.
* **JDK Toolchains:** 
  A configuração de toolchains no Gradle permite detetar, descarregar (se necessário) e isolar automaticamente a versão exata da JDK necessária para o projeto (neste caso, o Java 17), garantindo que o ambiente de build é independente do sistema operativo.

---

## 3. Tarefas Personalizadas Adicionadas

Para além da estrutura base, adicionámos e testámos tarefas customizadas no final do `build.gradle` para gerir a execução, testes e salvaguarda de ficheiros:

1. **`runServer` (Tipo `JavaExec`):**
   Cria uma tarefa dedicada a arrancar o servidor da aplicação de forma automatizada, apontando para a classe principal (`org.example.App`) e utilizando o `runtimeClasspath` do projeto.
2. **`backupSources` (Tipo `Copy`):**
   Automatiza o processo de salvaguarda, copiando os diretórios de código-fonte (`src/main` e `src/test`) diretamente para a pasta de build (`${buildDir}/backup`).
3. **`archiveBackup` (Tipo `Zip`):**
   Depende diretamente da tarefa anterior (`dependsOn backupSources`) para pegar na pasta de backup gerada e compactá-la num ficheiro `.zip` (`sources-backup.zip`) guardado na pasta de arquivos (`${buildDir}/archives`).

---

## 4. Validação e Testes no Terminal

Os seguintes comandos foram executados com sucesso no diretório do projeto para validar a integridade da build:

* **Executar os testes unitários (JUnit):**
  ```powershell
  .\gradlew.bat test
  ```
* **Executar a tarefa de arquivo ZIP (Backup encadeado):**
  ```powershell
  .\gradlew.bat archiveBackup
  ```
* **Inspecionar as toolchains ativas:**
  ```powershell
  .\gradlew.bat javaToolchains