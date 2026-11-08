# CA4 — Contentorização

Relatório do CA4. Cada parte tem o seu tutorial, com os passos, os resultados e as evidências.

| Parte | Conteúdo | Relatório |
| --- | --- | --- |
| Parte 1 | Imagens Docker do Chat e da Bookstore (v1, v2 e v3), comparação, `.dockerignore`, `docker history`, `docker stats`, utilizador não-root e publicação no Docker Hub | [Part1/README.md](Part1/README.md) · [Resultados](Part1/evidence/RESULTS.md) |
| Parte 2 | Bookstore com Docker Compose: proxy, web e db, healthchecks, rede, volume e persistência | [Part2/README.md](Part2/README.md) |
| Alternativa | A Parte 2 com Podman: pod, rootless, sem daemon, `kube play`, Quadlet e `podman compose` | [Alternative/README.md](Alternative/README.md) |

## Participação de cada membro

| Membro | Trabalho realizado | Contribuição |
| --- | --- | --- |
| Luiz Afonso | Parte 1: Dockerfiles v1, v2 e v3 do Chat e da Bookstore, scripts de construção e verificação, comparação das versões, publicação das imagens no Docker Hub; análise e desenho inicial da alternativa com Podman (abaixo) | 50% |
| João Paulo | Parte 2: Dockerfiles do db, web e proxy, `compose.yaml` com healthchecks, rede e volume, correção do `DataInitializer`, testes de persistência e conectividade, README; Alternativa: implementação com Podman, testes e README | 50% |

As percentagens são acordadas pelos dois membros e representam o trabalho efetivo de cada um.

## Alternativa: análise e desenho inicial

O Podman aceita os Dockerfiles usados pelo grupo. Isto permite comparar os motores mantendo o código Java, as tarefas Gradle e os clientes. No Windows, o Podman gere uma máquina Linux com `podman machine`. O tamanho e os recursos atribuídos a essa máquina influenciam os tempos de compilação e o consumo observado. Uma comparação de desempenho deve registar esses valores e usar as mesmas bases e condições de cache em ambos os motores. [Construção com Podman](https://docs.podman.io/en/latest/markdown/podman-build.1.html) · [Máquina Linux no Windows](https://docs.podman.io/en/latest/markdown/podman-machine.1.html)

Há dois níveis de permissões a considerar. Com Podman em modo *rootless*, o utilizador que executa os containers na máquina Linux tem privilégios limitados. Dentro da imagem, a instrução `USER app` define as permissões do próprio servidor Java. O desenho mantém essa instrução na v3 para que a aplicação só possa modificar os ficheiros acessíveis ao seu utilizador.

### Desenho e validação proposta

**Parte 1.** Na v1, o contexto deve incluir o bundle Git isolado da aplicação. Na v2, deve incluir os JARs produzidos pelo Gradle no Windows. Na v3, os fontes seguem para o estágio com JDK e apenas os artefactos passam ao estágio com JRE. Em cada construção seleciona-se explicitamente o ficheiro de exclusões da versão. Por exemplo, para a Bookstore v3, a partir da raiz do repositório:

```powershell
Push-Location ./CA4/Part1/source/CA1/week2
podman build -f Dockerfile.v3 --ignorefile Dockerfile.v3.dockerignore -t localhost/ca4-bookstore:v3 .
Pop-Location
podman run -d --name bookstore-podman -p 127.0.0.1:8084:8080 localhost/ca4-bookstore:v3
```

Com a aplicação pronta, o teste seria pedir `/actuator/health`, criar um livro e lê-lo por ID através da porta 8084. Para o Chat, publicar-se-ia a porta interna 59001 e repetir-se-ia a troca de mensagens entre dois clientes. A comparação recolheria o UID, o histórico de camadas e uma amostra de recursos após a mesma sequência de pedidos. No fim da experiência, `podman rm -f bookstore-podman` remove o container de demonstração.

**Parte 2.** O desenho usa uma rede onde o proxy resolve `web` e a aplicação resolve `db`. Só o proxy publica uma porta no Windows. Um volume nomeado guarda os ficheiros do H2. O arranque deve aguardar pela disponibilidade da base de dados antes da aplicação e pela saúde da aplicação antes do proxy. Como `podman compose` delega a execução num fornecedor Compose externo, a validação deve identificar o fornecedor e a versão, confirmar a ordem de arranque e testar os pedidos através do proxy. Para demonstrar persistência, criar um livro, recriar os containers mantendo o volume e consultar o mesmo ID. [Funcionamento de podman compose](https://docs.podman.io/en/latest/markdown/podman-compose.1.html)

**Estado da alternativa.** O desenho acima foi implementado e validado para a Parte 2 com Podman 5.8 no Windows. A implementação usa um pod para a aplicação e a base de dados (a aplicação liga-se ao H2 por `localhost`), em vez de containers separados que se resolvem por nome. Os passos, resultados e limitações estão no [README da alternativa](Alternative/README.md). A Parte 1 não foi repetida com Podman: as medições publicadas foram obtidas com Docker.
