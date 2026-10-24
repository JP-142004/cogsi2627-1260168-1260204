# Run from PowerShell. Only bootstrap Ansible and SSH here; services use roles.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Ca3Vm {
    param([string]$Machine, [string]$Command)
    & vagrant ssh $Machine -c $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed on VM '$Machine'."
    }
}

function Get-Ca3PublicKey {
    param([string[]]$Lines)
    $key = @($Lines | Where-Object { $_ -match '^ssh-ed25519 [A-Za-z0-9+/=]+( |$)' })
    if ($key.Count -ne 1) {
        throw 'Expected exactly one Ed25519 public key.'
    }
    $parts = $key[0] -split '\s+'
    return "ssh-ed25519 $($parts[1])"
}

Push-Location $PSScriptRoot
try {
    & vagrant validate
    if ($LASTEXITCODE -ne 0) { throw 'Invalid Vagrant configuration.' }

    & vagrant up --provider=virtualbox
    if ($LASTEXITCODE -ne 0) { throw 'Could not start all VMs.' }

    # Existing VMs need one reload to mount the newly added shared folder.
    & vagrant ssh app -c 'test -f /mnt/ca3-ansible/site.yml'
    if ($LASTEXITCODE -ne 0) {
        & vagrant reload app
        if ($LASTEXITCODE -ne 0) { throw 'Could not reload app.' }
    }

    Write-Host 'Preparing Ansible on app...'
    Invoke-Ca3Vm app 'command -v ansible >/dev/null || (sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible)'
    Invoke-Ca3Vm app "umask 077; mkdir -p ~/.ssh; test -f ~/.ssh/ca3_ansible || ssh-keygen -q -t ed25519 -f ~/.ssh/ca3_ansible -N '' -C ca3-controller"
    $controllerKey = Get-Ca3PublicKey -Lines @(Invoke-Ca3Vm app 'cat ~/.ssh/ca3_ansible.pub')

    foreach ($machine in @('db', 'proxy')) {
        Write-Host "Authorizing controller on $machine..."
        Invoke-Ca3Vm $machine "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; grep -qF '$controllerKey' ~/.ssh/authorized_keys || printf '%s\n' '$controllerKey' >> ~/.ssh/authorized_keys"

        # Fetch the host identity through Vagrant's authenticated SSH connection.
        $hostKey = Get-Ca3PublicKey -Lines @(Invoke-Ca3Vm $machine 'cat /etc/ssh/ssh_host_ed25519_key.pub')
        $address = if ($machine -eq 'db') { '192.168.56.30' } else { '192.168.56.20' }
        $entry = "$address $hostKey"
        Invoke-Ca3Vm app "touch ~/.ssh/known_hosts; grep -qxF '$entry' ~/.ssh/known_hosts || { ssh-keygen -R '$address' >/dev/null 2>&1; printf '%s\n' '$entry' >> ~/.ssh/known_hosts; }"
    }

    Write-Host 'Copying the versioned Ansible files to the controller...'
    Invoke-Ca3Vm app 'set -e; mkdir -p ~/ca3/ansible; tar --exclude=evidence --exclude=*.bak -cf - -C /mnt/ca3-ansible . | tar --no-same-owner --no-same-permissions -xf - -C ~/ca3/ansible'

    Write-Host 'Checking Ansible connectivity and sudo...'
    Invoke-Ca3Vm app 'cd ~/ca3/ansible && ansible all -i hosts.ini -m ping && ansible all -i hosts.ini -b -m command -a whoami && ansible-playbook -i hosts.ini site.yml --syntax-check'
    Write-Host 'Preparation completed. Services were not provisioned by this script.'
    Write-Host 'Next: vagrant ssh app'
    Write-Host 'Then: cd ~/ca3/ansible && ansible-playbook -i hosts.ini site.yml'
}
finally {
    Pop-Location
}
