# Resultados locais — CA4 Parte 1

Uma medição por imagem, sem cache das instruções de build; bases já disponíveis. Valores em MiB (1 MiB = 1048576 bytes).

| Imagem | Docker build (s) | Host, incluindo testes (s) | Total (s) | MiB | Camadas de ficheiros | UID | Resultado |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| ca4-chat:v1 | 32,55 | 0,00 | 32,55 | 1047,43 | 11 | 0 | PASS |
| ca4-chat:v2 | 1,91 | 26,76 | 28,67 | 411,47 | 8 | 0 | PASS |
| ca4-chat:v3 | 18,98 | 0,00 | 18,98 | 411,52 | 9 | 999 | PASS |
| ca4-bookstore:v1 | 45,45 | 0,00 | 45,45 | 1306,91 | 11 | 0 | PASS |
| ca4-bookstore:v2 | 6,09 | 47,02 | 53,11 | 500,37 | 8 | 0 | PASS |
| ca4-bookstore:v3 | 35,38 | 0,00 | 35,38 | 500,41 | 9 | 999 | PASS |

## Verificação funcional

- **ca4-chat:v1**: Dois clientes no host registados; mensagens recebidas nos dois sentidos. UID: 0.
- **ca4-chat:v2**: Dois clientes no host registados; mensagens recebidas nos dois sentidos. UID: 0.
- **ca4-chat:v3**: Dois clientes no host registados; mensagens recebidas nos dois sentidos. UID: 999.
- **ca4-bookstore:v1**: Health UP; listagem, criação e leitura do livro 3 pelo host. UID: 0.
- **ca4-bookstore:v2**: Health UP; listagem, criação e leitura do livro 3 pelo host. UID: 0.
- **ca4-bookstore:v3**: Health UP; listagem, criação e leitura do livro 3 pelo host. UID: 999.

## Amostras de recursos após atividade dos clientes

| Imagem | CPU | Memória / limite | Rede | I/O de blocos |
| --- | ---: | --- | --- | --- |
| ca4-chat:v1 | 0.10% | 56.92MiB / 15.33GiB | 2.57kB / 1.78kB | 16.2MB / 0B |
| ca4-chat:v2 | 0.14% | 58.78MiB / 15.33GiB | 2.7kB / 1.78kB | 24.4MB / 0B |
| ca4-chat:v3 | 0.16% | 53.77MiB / 15.33GiB | 2.73kB / 1.71kB | 0B / 0B |
| ca4-bookstore:v1 | 0.13% | 402.6MiB / 15.33GiB | 4.23kB / 3.65kB | 147kB / 0B |
| ca4-bookstore:v2 | 0.17% | 381.2MiB / 15.33GiB | 4.29kB / 3.59kB | 52.7MB / 0B |
| ca4-bookstore:v3 | 0.16% | 433.2MiB / 15.33GiB | 4.16kB / 3.59kB | 4.1kB / 0B |

Os testes unitários existentes passaram no host: um no Chat e um na Bookstore. A verificação funcional acrescenta clientes TCP e pedidos HTTP reais às seis imagens.

As versões v3 usam UID diferente de zero. Git e javac estão presentes apenas na v1. Os containers temporários foram removidos depois dos testes.

Os tempos da v2 incluem compilação e testes no host; v1/v3 compilam e empacotam dentro da imagem. Consultar as limitações da medição no README. As amostras de recursos são pontuais, não máximos.

Os IDs, commits e instantes das medições encontram-se em images.json e verification.json. Os logs de construção e históricos completos acompanham estes resultados.
