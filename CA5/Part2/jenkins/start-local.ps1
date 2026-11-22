param([switch]$RefreshScm)
$ErrorActionPreference = 'Stop'
$partDirectory = Split-Path -Parent $PSScriptRoot
Push-Location $partDirectory
try {
    vagrant up production --provider virtualbox
    if ($LASTEXITCODE -ne 0) { throw 'Falhou o arranque da VM.' }
    docker compose -f jenkins/compose.yaml build jenkins
    if ($LASTEXITCODE -ne 0) { throw 'Falhou a construção do Jenkins.' }
    $prepareArguments = @('-3', 'jenkins/prepare-local.py')
    if ($RefreshScm) { $prepareArguments += '--refresh-scm' }
    & py @prepareArguments
    if ($LASTEXITCODE -ne 0) { throw 'Falhou a preparação local.' }
    $env:CA5_SSH_PORT = (vagrant port production --guest 22).Trim()
    docker compose -f jenkins/compose.yaml up -d
    if ($LASTEXITCODE -ne 0) { throw 'Falhou o arranque do laboratório.' }
    Write-Output 'Jenkins: http://localhost:18080/ (utilizador luiz)'
    Write-Output 'Palavra-passe local: CA5/Part2/.local/secrets/admin_password'
    Write-Output 'E-mails de teste: http://localhost:18025/'
} finally {
    Pop-Location
}
