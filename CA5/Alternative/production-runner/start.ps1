param([switch]$UseExistingRegistrationToken)
$ErrorActionPreference = 'Stop'
$partDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) '../Part2'
$tokenPath = Join-Path $partDirectory '.local/secrets/github_runner_registration_token'
if (-not $UseExistingRegistrationToken) {
    # O GitHub exige um administrador para emitir este token temporário.
    $registrationToken = & gh api --method POST repos/JP-142004/cogsi2627-1260168-1260204/actions/runners/registration-token --jq .token
    if ($LASTEXITCODE -ne 0) { throw 'O administrador do repositório tem de emitir o token de registo.' }
    [System.IO.File]::WriteAllText($tokenPath, $registrationToken.Trim(), [System.Text.UTF8Encoding]::new($false))
    $registrationToken = $null
}
if (-not (Test-Path -LiteralPath $tokenPath)) { throw 'Falta o ficheiro local com o token de registo.' }
Push-Location $partDirectory
try {
    $sshPort = (& vagrant port production --guest 22).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível obter a porta SSH da VM.' }
} finally {
    Pop-Location
}
& gh variable set CA5_PRODUCTION_HOST -R JP-142004/cogsi2627-1260168-1260204 --body host.docker.internal
if ($LASTEXITCODE -ne 0) { throw 'Falhou a configuração do endereço acessível pelo runner.' }
& gh variable set CA5_PRODUCTION_SSH_PORT -R JP-142004/cogsi2627-1260168-1260204 --body $sshPort
if ($LASTEXITCODE -ne 0) { throw 'Falhou a configuração da porta SSH.' }
docker compose -f (Join-Path $PSScriptRoot 'compose.yaml') up -d --build
if ($LASTEXITCODE -ne 0) { throw 'Falhou o arranque do runner.' }
Write-Output 'Runner efémero iniciado para um job. A chave SSH continua local; não foi enviada para o GitHub.'
Write-Output 'Consulta o estado nos Settings > Actions > Runners do repositório.'
