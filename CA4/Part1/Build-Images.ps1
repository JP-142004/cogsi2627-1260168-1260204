param([switch]$NoCache)
$ErrorActionPreference = 'Stop'
$partRoot = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $partRoot '../..')).Path
$evidence = Join-Path $partRoot 'evidence'
New-Item -ItemType Directory -Force $evidence | Out-Null
$env:GRADLE_USER_HOME = Join-Path $partRoot '.cache/gradle'
if (-not $env:JAVA_HOME) {
    $env:JAVA_HOME = Split-Path (Split-Path (Get-Command java).Source)
}
function Assert-Exit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step falhou (código $LASTEXITCODE)." }
}
$sourceRef = (& git -C $repoRoot branch --show-current).Trim()
Assert-Exit 'Consulta do ramo'
if (-not $sourceRef) { throw 'Selecione um ramo antes de criar o bundle.' }
$apps = @{
    chat = @{ Path = 'source/CA1/week1/build_tools/gradle_demo'; Task = ':app:packageApp' }
    bookstore = @{ Path = 'source/CA1/week2'; Task = ':app:bootJar' }
}
$results = @()
foreach ($name in @('chat', 'bookstore')) {
    $context = Join-Path $partRoot $apps[$name].Path
    Push-Location $context
    try {
        # The bundle stays local and is excluded from Git and v3 build contexts.
        & git -C $repoRoot bundle create (Join-Path $context 'source.bundle') $sourceRef
        Assert-Exit 'Criação do bundle'
        $timer = [Diagnostics.Stopwatch]::StartNew()
        & ./gradlew.bat --no-daemon :app:clean :app:test $apps[$name].Task 2>&1 |
            Tee-Object -FilePath (Join-Path $evidence "$name-host-build.txt")
        Assert-Exit 'Compilação e testes no host'
        $timer.Stop()
        $hostSeconds = $timer.Elapsed.TotalSeconds
        foreach ($version in 1..3) {
            $image = "ca4-${name}:v$version"
            $buildArgs = @('build', '--progress=plain', '-f', "Dockerfile.v$version", '-t', $image)
            if ($version -eq 1) { $buildArgs += @('--build-arg', "SOURCE_REF=$sourceRef") }
            if ($NoCache) { $buildArgs += '--no-cache' }
            $buildArgs += '.'
            $timer.Restart()
            & docker @buildArgs 2>&1 | Tee-Object -FilePath (Join-Path $evidence "$name-v$version-build.txt")
            Assert-Exit "Construção $image"
            $timer.Stop()
            $buildSeconds = $timer.Elapsed.TotalSeconds
            $details = (& docker image inspect $image | ConvertFrom-Json)[0]
            Assert-Exit "Inspeção $image"
            & docker history --no-trunc $image | Set-Content (Join-Path $evidence "$name-v$version-history.txt")
            Assert-Exit "Histórico $image"
            $results += [pscustomobject]@{
                image = $image; imageId = $details.Id; bytes = $details.Size
                filesystemLayers = $details.RootFS.Layers.Count
                dockerBuildSeconds = [Math]::Round($buildSeconds, 2)
                hostBuildSeconds = $(if ($version -eq 2) { [Math]::Round($hostSeconds, 2) } else { 0 })
                user = $details.Config.User; noCache = [bool]$NoCache
                sourceCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
                measuredAt = [DateTimeOffset]::Now.ToString('o')
            }
            $results | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $evidence 'images.json')
        }
    } finally { Pop-Location }
}
$results | Format-Table image, dockerBuildSeconds, hostBuildSeconds, bytes, filesystemLayers, user
