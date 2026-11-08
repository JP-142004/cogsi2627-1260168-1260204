$ErrorActionPreference = 'Stop'
$evidence = Join-Path $PSScriptRoot 'evidence'
$images = Get-Content (Join-Path $evidence 'images.json') -Raw | ConvertFrom-Json
$checks = Get-Content (Join-Path $evidence 'verification.json') -Raw | ConvertFrom-Json
if ($images.Count -ne 6 -or $checks.Count -ne 6) { throw 'São necessárias seis imagens e seis verificações.' }
$lines = @(
    '# Resultados locais — CA4 Parte 1',
    '',
    'Uma medição por imagem. O campo noCache em images.json indica se a cache das instruções Docker foi desativada. Valores em MiB (1 MiB = 1048576 bytes).',
    '',
    '| Imagem | Docker build (s) | Host, incluindo testes (s) | Total (s) | MiB | Camadas de ficheiros | UID | Resultado |',
    '| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |'
)
foreach ($item in $images) {
    $check = $checks | Where-Object image -EQ $item.image
    if ($check.imageId -ne $item.imageId -or $check.result -ne 'PASS') { throw "Verificação desatualizada: $($item.image)" }
    $lines += '| {0} | {1:F2} | {2:F2} | {3:F2} | {4:F2} | {5} | {6} | {7} |' -f `
        $item.image, $item.dockerBuildSeconds, $item.hostBuildSeconds, `
        ($item.dockerBuildSeconds + $item.hostBuildSeconds), ($item.bytes / 1MB), `
        $item.filesystemLayers, $check.uid, $check.result
}
$lines += @('', '## Verificação funcional', '')
foreach ($check in $checks) { $lines += "- **$($check.image)**: $($check.detail) UID: $($check.uid)." }
$lines += @('', '## Amostras de recursos após atividade dos clientes', '',
    '| Imagem | CPU | Memória / limite | Rede | I/O de blocos |',
    '| --- | ---: | --- | --- | --- |')
foreach ($check in $checks) {
    $stats = $check.stats
    $lines += "| $($check.image) | $($stats.CPUPerc) | $($stats.MemUsage) | $($stats.NetIO) | $($stats.BlockIO) |"
}
$lines += @('',
    'Os testes unitários existentes passaram no host: um no Chat e um na Bookstore. A verificação funcional acrescenta clientes TCP e pedidos HTTP reais às seis imagens.',
    '',
    'As versões v3 usam UID diferente de zero. Git e javac estão presentes apenas na v1. Os containers temporários foram removidos depois dos testes.',
    '',
    'Os tempos da v2 incluem compilação e testes no host; v1/v3 compilam e empacotam dentro da imagem. Consultar as limitações da medição no README. As amostras de recursos são pontuais, não máximos.',
    '',
    'Os IDs, commits e instantes das medições encontram-se em images.json e verification.json. Os logs de construção e históricos completos acompanham estes resultados.')
$lines | Set-Content -Encoding utf8 (Join-Path $evidence 'RESULTS.md')
