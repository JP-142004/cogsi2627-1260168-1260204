# Resultados locais — CA4 Parte 1

Uma medição por imagem. O campo noCache em images.json indica se a cache das instruções Docker foi desativada. Valores em MiB (1 MiB = 1048576 bytes).

| Imagem | Docker build (s) | Host, incluindo testes (s) | Total (s) | MiB | Camadas de ficheiros | UID | Resultado |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| ca4-chat:v1 | 61,98 | 0,00 | 61,98 | 1044,19 | 11 | 0 | PASS |
| ca4-chat:v2 | 8,13 | 22,08 | 30,21 | 411,82 | 8 | 0 | PASS |
| ca4-chat:v3 | 24,96 | 0,00 | 24,96 | 411,86 | 9 | 999 | PASS |
| ca4-bookstore:v1 | 66,73 | 0,00 | 66,73 | 1303,81 | 11 | 0 | PASS |
| ca4-bookstore:v2 | 6,66 | 29,45 | 36,11 | 500,71 | 8 | 0 | PASS |
| ca4-bookstore:v3 | 41,99 | 0,00 | 41,99 | 500,75 | 9 | 999 | PASS |

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
| ca4-chat:v1 | 0.17% | 59.71MiB / 15.33GiB | 2.87kB / 1.74kB | 13.8MB / 0B |
| ca4-chat:v2 | 0.14% | 57.39MiB / 15.33GiB | 2.72kB / 1.74kB | 0B / 0B |
| ca4-chat:v3 | 0.15% | 60.38MiB / 15.33GiB | 2.5kB / 1.74kB | 0B / 0B |
| ca4-bookstore:v1 | 0.35% | 417.2MiB / 15.33GiB | 4.62kB / 3.65kB | 0B / 0B |
| ca4-bookstore:v2 | 0.19% | 444.4MiB / 15.33GiB | 4.53kB / 3.69kB | 0B / 0B |
| ca4-bookstore:v3 | 0.20% | 467.4MiB / 15.33GiB | 4.55kB / 3.71kB | 4.1kB / 0B |

Os testes unitários existentes passaram no host: um no Chat e um na Bookstore. A verificação funcional acrescenta clientes TCP e pedidos HTTP reais às seis imagens.

As versões v3 usam UID diferente de zero. Git e javac estão presentes apenas na v1. Os containers temporários foram removidos depois dos testes.

Os tempos da v2 incluem compilação e testes no host; v1/v3 compilam e empacotam dentro da imagem. Consultar as limitações da medição no README. As amostras de recursos são pontuais, não máximos.

Os IDs, commits e instantes das medições encontram-se em images.json e verification.json. Os logs de construção e históricos completos acompanham estes resultados.
