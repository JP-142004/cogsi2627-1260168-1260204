# podman-demo.ps1 - Alternativa ao Docker Compose com Podman.
# Demonstra: Podman sem daemon, execucao rootless, pod (web + db), rede e volume
# Podman, kube generate / kube play, Quadlet (systemd) e suporte a Compose.
#
# Correr no PowerShell, a partir da pasta CA4\Alternative:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\podman-demo.ps1
#
# Antes: Podman instalado e a maquina iniciada (podman machine start).
# Cada passo guarda a saida em evidence\NN-nome.txt e um print do ecra em
# evidence\NN-nome.png. Mantem a janela do PowerShell maximizada.
# Para nao tirar prints: .\podman-demo.ps1 -SemPrints

param(
    [switch]$SemPrints,
    [int]$Porta = 8085
)

$ErrorActionPreference = 'Continue'
$Here = $PSScriptRoot
$Part2 = (Resolve-Path (Join-Path $Here '..\Part2')).Path
$Ev = Join-Path $Here 'evidence'
New-Item -ItemType Directory -Force $Ev | Out-Null

# Caminho desta pasta dentro da maquina Podman (WSL monta C:\ em /mnt/c).
$HereLinux = '/mnt/' + $Here.Substring(0, 1).ToLower() + ($Here.Substring(2) -replace '\\', '/')

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function Save-Print([string]$Nome) {
    if ($SemPrints) { return }
    Start-Sleep -Milliseconds 700
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $bmp.Save((Join-Path $Ev "$Nome.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

function Step([int]$N, [string]$Slug, [string]$Titulo, [scriptblock]$Acao) {
    $nome = '{0:D2}-{1}' -f $N, $Slug
    Write-Host ''
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Write-Host "$N. $Titulo" -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Read-Host 'Enter para executar' | Out-Null
    Clear-Host
    Write-Host "$N. $Titulo" -ForegroundColor Cyan
    Write-Host ''
    $saida = & $Acao | Out-String -Width 200
    Write-Host $saida
    "# $N. $Titulo`r`n`r`n$saida" | Out-File -Encoding utf8 (Join-Path $Ev "$nome.txt")
    Save-Print $nome
}

function Show([string]$Cmd) {
    # Mostra o comando antes do resultado, como num terminal.
    "PS> $Cmd"
}

function Wait-Healthy([string]$Ctr, [int]$Tentativas = 40) {
    for ($i = 1; $i -le $Tentativas; $i++) {
        podman healthcheck run $Ctr *> $null
        if ($LASTEXITCODE -eq 0) { "$Ctr healthy (tentativa $i)"; return }
        Start-Sleep -Seconds 3
    }
    "$Ctr NAO ficou healthy"
}

$dbHealth = "java -cp /opt/h2.jar org.h2.tools.Shell -url jdbc:h2:tcp://localhost:9092/./bookstore -user sa -password '' -sql 'SELECT 1' | grep -q 1"
$webHealth = 'wget -qO- http://localhost:8080/actuator/health | grep -q UP'

# Limpeza de execucoes anteriores (o volume e mantido de proposito).
podman machine ssh 'systemctl --user stop bookstore-proxy.service bookstore.service 2>/dev/null; true' *> $null
podman pod rm -f bookstore *> $null
podman rm -f bookstore-proxy *> $null

Step 1 'sem-daemon-rootless' 'Podman: sem daemon central e sem root' {
    Show 'podman version'; podman version
    ''
    Show 'podman machine list'; podman machine list
    ''
    Show 'podman info (rootless e backend de rede)'
    podman info --format 'Rootless={{.Host.Security.Rootless}}  Rede={{.Host.NetworkBackend}}  OS={{.Host.Distribution.Distribution}}'
    ''
    Show 'na maquina Podman: existe algum daemon residente?'
    podman machine ssh "pgrep -a dockerd || echo 'dockerd: nao existe'; pgrep -a containerd || echo 'containerd: nao existe'; systemctl --user is-active podman.socket"
}

Step 2 'build' 'Construir as tres imagens da Parte 2 com Podman (Buildah)' {
    foreach ($svc in 'db', 'web', 'proxy') {
        Write-Host "A construir bookstore-${svc}..." -ForegroundColor Yellow
        podman build -q -t "localhost/bookstore-${svc}:ca4" (Join-Path $Part2 $svc) | Out-Host
    }
    Show 'podman images'
    podman images --filter reference=localhost/bookstore-*
}

Step 3 'rede-volume' 'Rede e volume geridos pelo Podman' {
    Show 'podman network create bookstore-net'; podman network create --ignore bookstore-net
    Show 'podman volume create bookstore-h2'; podman volume create --ignore bookstore-h2
    ''
    Show 'podman network ls'; podman network ls
    ''
    Show 'podman volume ls'; podman volume ls
}

Step 4 'pod' 'Criar o pod bookstore (web e db partilham a rede)' {
    Show 'podman pod create --name bookstore --network bookstore-net --network-alias web'
    podman pod create --name bookstore --network bookstore-net --network-alias web
    ''
    Show 'podman pod ps'; podman pod ps
    ''
    Show 'podman ps -a --pod  (o pod ja tem o container infra)'; podman ps -a --pod
}

Step 5 'db' 'Arrancar o H2 dentro do pod e esperar que fique healthy' {
    Show 'podman run -d --pod bookstore --name bookstore-db -v bookstore-h2:/data --health-cmd ... localhost/bookstore-db:ca4'
    podman run -d --pod bookstore --name bookstore-db -v bookstore-h2:/data `
        --health-cmd $dbHealth --health-interval 10s --health-timeout 5s --health-retries 6 --health-start-period 10s `
        localhost/bookstore-db:ca4
    Wait-Healthy 'bookstore-db'
}

Step 6 'web' 'Arrancar a Bookstore no mesmo pod (H2 em localhost)' {
    Show 'podman run -d --pod bookstore --name bookstore-web -e SPRING_DATASOURCE_URL=jdbc:h2:tcp://localhost:9092/./bookstore ...'
    podman run -d --pod bookstore --name bookstore-web `
        -e SPRING_DATASOURCE_URL=jdbc:h2:tcp://localhost:9092/./bookstore `
        -e SPRING_DATASOURCE_USERNAME=sa -e SPRING_DATASOURCE_PASSWORD= -e SERVER_PORT=8080 `
        --health-cmd $webHealth --health-interval 10s --health-timeout 5s --health-retries 6 --health-start-period 30s `
        localhost/bookstore-web:ca4
    Wait-Healthy 'bookstore-web'
}

Step 7 'proxy' "Arrancar o proxy fora do pod e publicar a porta $Porta" {
    Show "podman run -d --name bookstore-proxy --network bookstore-net -p ${Porta}:80 localhost/bookstore-proxy:ca4"
    podman run -d --name bookstore-proxy --network bookstore-net -p "${Porta}:80" localhost/bookstore-proxy:ca4
    Start-Sleep -Seconds 2
    ''
    Show 'podman ps --pod'; podman ps --pod
}

Step 8 'http' 'Pedidos HTTP pelo proxy' {
    Show "curl.exe -i http://localhost:$Porta/books"; curl.exe -s -i "http://localhost:$Porta/books"
    ''
    ''
    Show "curl.exe http://localhost:$Porta/actuator/health"; curl.exe -s "http://localhost:$Porta/actuator/health"
}

Step 9 'rede-pod' 'Comunicacao: dentro do pod por localhost, entre pod e proxy por nome' {
    Show 'podman pod inspect bookstore (namespaces partilhados)'
    podman pod inspect bookstore --format 'Pod={{.Name}}  Partilhado={{.SharedNamespaces}}  Infra={{.InfraContainerID}}'
    ''
    Show 'podman exec bookstore-web printenv SPRING_DATASOURCE_URL'
    podman exec bookstore-web printenv SPRING_DATASOURCE_URL
    ''
    Show 'podman exec bookstore-web wget -qO- http://localhost:8080/actuator/health'
    podman exec bookstore-web wget -qO- http://localhost:8080/actuator/health
    ''
    ''
    Show 'podman exec bookstore-proxy getent hosts web'
    podman exec bookstore-proxy getent hosts web
}

Step 10 'rootless' 'Rootless: utilizador no container vs utilizador no host' {
    Show 'podman top bookstore-web user huser args'; podman top bookstore-web user huser args
    ''
    Show 'podman top bookstore-db user huser args'; podman top bookstore-db user huser args
    ''
    Show 'podman unshare cat /proc/self/uid_map  (mapeamento de UIDs, na maquina Podman)'
    podman machine ssh 'podman unshare cat /proc/self/uid_map'
    ''
    Show 'na maquina Podman: processos dos containers (um conmon por container, sem daemon)'
    podman machine ssh "ps -eo user,pid,ppid,comm | grep -E 'conmon|java|nginx' | grep -v grep"
}

Step 11 'kube-persistencia' 'kube generate, apagar o pod, kube play e persistencia' {
    $livro = @{ title = 'Livro de teste Podman'; author = 'Joao'; price = 12.5 } | ConvertTo-Json
    $criado = Invoke-RestMethod -Method Post -Uri "http://localhost:$Porta/books" -ContentType 'application/json' -Body $livro
    "Livro criado com id $($criado.id)"
    ''
    Show 'podman kube generate bookstore -f evidence\kube-generated.yaml'
    podman kube generate bookstore -f (Join-Path $Ev 'kube-generated.yaml')
    ''
    Show 'podman pod rm -f bookstore  (apaga web, db e infra; o volume fica)'
    podman pod rm -f bookstore
    Show 'podman volume ls'; podman volume ls
    ''
    Show 'podman kube play --network bookstore-net:alias=web kube\bookstore-pod.yaml'
    podman kube play --network bookstore-net:alias=web (Join-Path $Here 'kube\bookstore-pod.yaml')
    Wait-Healthy 'bookstore-db'
    Wait-Healthy 'bookstore-web'
    podman restart bookstore-proxy | Out-Null   # o Nginx resolve "web" ao arrancar
    Start-Sleep -Seconds 2
    ''
    Show "curl.exe http://localhost:$Porta/books/$($criado.id)"
    curl.exe -s "http://localhost:$Porta/books/$($criado.id)"
}

Step 12 'quadlet' 'Quadlet: o pod e o proxy como servicos systemd' {
    podman pod rm -f bookstore | Out-Null
    podman rm -f bookstore-proxy | Out-Null
    Show 'copiar os ficheiros Quadlet para ~/.config/containers/systemd na maquina Podman'
    podman machine ssh "mkdir -p ~/.config/containers/systemd ~/ca4-podman && cp $HereLinux/quadlet/* ~/.config/containers/systemd/ && cp $HereLinux/kube/bookstore-pod.yaml ~/ca4-podman/ && ls ~/.config/containers/systemd"
    ''
    Show 'systemctl --user daemon-reload && systemctl --user start bookstore-proxy.service'
    podman machine ssh 'systemctl --user daemon-reload && systemctl --user start bookstore-proxy.service'
    Wait-Healthy 'bookstore-db'
    Wait-Healthy 'bookstore-web'
    ''
    Show 'systemctl --user status (resumo)'
    podman machine ssh "systemctl --user --no-pager status bookstore.service bookstore-proxy.service | grep -E 'service -|Active:|Loaded:'"
    ''
    Show "curl.exe http://localhost:$Porta/books"; curl.exe -s "http://localhost:$Porta/books"
}

Step 13 'quadlet-restart' 'systemd recupera o proxy depois de uma falha' {
    Show 'podman kill bookstore-proxy'; podman kill bookstore-proxy
    Start-Sleep -Seconds 8
    ''
    Show 'podman ps (o proxy voltou, recriado pelo systemd)'; podman ps --format '{{.Names}}  {{.Status}}'
    ''
    Show 'journalctl --user -u bookstore-proxy.service (ultimas linhas)'
    podman machine ssh 'journalctl --user -u bookstore-proxy.service --no-pager -n 8'
    ''
    Show 'systemctl --user cat bookstore.service (unidade gerada pelo Quadlet)'
    podman machine ssh "systemctl --user cat bookstore.service | grep -E '^#|ExecStart|Requires|After'"
}

Step 14 'compose' 'Suporte a Compose: o compose.yaml da Parte 2 com podman compose' {
    podman machine ssh 'systemctl --user stop bookstore-proxy.service bookstore.service' | Out-Null
    Show 'podman compose version'; podman compose version
    ''
    $env:PROXY_PORT = '8086'
    Show 'podman compose -f ..\Part2\compose.yaml -p bookstore-podcompose up -d  (PROXY_PORT=8086)'
    podman compose -f (Join-Path $Part2 'compose.yaml') -p bookstore-podcompose up -d 2>&1 | Out-String
    Start-Sleep -Seconds 5
    Show 'podman ps'; podman ps --format '{{.Names}}  {{.Status}}  {{.Ports}}'
    ''
    Show 'curl.exe http://localhost:8086/books'; curl.exe -s http://localhost:8086/books
    ''
    podman compose -f (Join-Path $Part2 'compose.yaml') -p bookstore-podcompose down 2>&1 | Out-Null
    Remove-Item Env:PROXY_PORT
}

Write-Host ''
Write-Host "Demonstracao concluida. Evidencias em $Ev" -ForegroundColor Green
Write-Host 'Para voltar a ligar o pod e o proxy pelo systemd:' -ForegroundColor Green
Write-Host "  podman machine ssh 'systemctl --user start bookstore-proxy.service'" -ForegroundColor Green
