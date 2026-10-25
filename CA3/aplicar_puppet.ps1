# aplicar_puppet.ps1
# Cria a implementacao Puppet (alternativa, modo masterless) da parte de seguranca do CA3.
# Os ficheiros ficam em CA3/ansible/puppet/ para o prepare.ps1 os copiar para a VM app.
# Executar a partir da pasta CA3:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\aplicar_puppet.ps1

$ErrorActionPreference = 'Stop'
$root = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'ansible\puppet'
$utf8 = New-Object System.Text.UTF8Encoding $false

function Write-PuppetFile {
    param([string]$Relative, [string]$Content)
    $path = Join-Path $root $Relative
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $text = $Content.Replace("`r`n", "`n").TrimEnd("`n") + "`n"
    [System.IO.File]::WriteAllText($path, $text, $utf8)
    Write-Host "Escrito: ansible/puppet/$Relative"
}

Write-PuppetFile 'manifests/site.pp' @'
# Ponto de entrada do puppet apply (masterless).
include security
'@

Write-PuppetFile 'modules/security/manifests/init.pp' @'
# Versao Puppet da role Ansible "security" (CA3, alternativa).
#
# Cobre: grupo developers, utilizador devuser, politica PAM (complexidade,
# historico e bloqueio), contas de servico h2/bookstore e permissoes de
# /var/lib/h2 (db) e /opt/bookstore, /etc/bookstore (app).
#
# Nao cobre: instalacao e arranque dos servicos H2, Bookstore e Nginx,
# que continuam a ser geridos pelas roles Ansible.
class security {
  $developers = 'developers'
  $dev_user   = 'devuser'
  $host       = $facts['networking']['hostname']

  package { ['libpam-pwquality', 'libpam-modules']:
    ensure => present,
  }

  group { $developers:
    ensure => present,
  }

  # A password de devuser nao e gerida pelo Puppet (definida com passwd),
  # tal como o update_password: on_create na role Ansible.
  user { $dev_user:
    ensure     => present,
    shell      => '/bin/bash',
    managehome => true,
    groups     => [$developers],
    require    => Group[$developers],
  }

  # Substitui o ficheiro inteiro: os valores por omissao do Ubuntu nao sao mantidos.
  file { '/etc/security/pwquality.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "minlen = 12\nminclass = 3\n",
    require => Package['libpam-pwquality'],
  }

  file { '/etc/security/faillock.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "deny = 5\nunlock_time = 600\nfail_interval = 900\n",
  }

  file { '/etc/pam.d/common-auth':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    source  => 'puppet:///modules/security/common-auth',
    require => Package['libpam-modules'],
  }

  file { '/etc/pam.d/common-account':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    source  => 'puppet:///modules/security/common-account',
    require => Package['libpam-modules'],
  }

  file { '/etc/pam.d/common-password':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    source  => 'puppet:///modules/security/common-password',
    require => Package['libpam-pwquality'],
  }

  case $host {
    /db$/: {
      group { 'h2':
        ensure => present,
        system => true,
      }

      user { 'h2':
        ensure     => present,
        system     => true,
        gid        => 'h2',
        shell      => '/usr/sbin/nologin',
        managehome => false,
        groups     => [$developers],
        require    => [Group['h2'], Group[$developers]],
      }

      # setgid (2770): os ficheiros novos herdam o grupo developers.
      # Sem recurse, para nao haver alteracoes em cada execucao.
      file { '/var/lib/h2':
        ensure  => directory,
        owner   => 'h2',
        group   => $developers,
        mode    => '2770',
        require => User['h2'],
      }

      file { '/etc/systemd/system/h2-server.service.d':
        ensure => directory,
        owner  => 'root',
        group  => 'root',
        mode   => '0755',
      }

      file { '/etc/systemd/system/h2-server.service.d/umask.conf':
        ensure  => file,
        owner   => 'root',
        group   => 'root',
        mode    => '0644',
        content => "[Service]\nUMask=0007\n",
      }
    }

    /app$/: {
      group { 'bookstore':
        ensure => present,
        system => true,
      }

      user { 'bookstore':
        ensure     => present,
        system     => true,
        gid        => 'bookstore',
        shell      => '/usr/sbin/nologin',
        managehome => false,
        groups     => [$developers],
        require    => [Group['bookstore'], Group[$developers]],
      }

      file { ['/opt/bookstore', '/etc/bookstore']:
        ensure => directory,
        owner  => 'root',
        group  => $developers,
        mode   => '0750',
      }
    }

    default: {
      notice("security: host ${host} sem papel especifico; so a politica comum foi aplicada.")
    }
  }
}
'@

Write-PuppetFile 'modules/security/files/common-auth' @'
# Gerido pelo Puppet (modulo security). Base: Ubuntu 22.04 + pam_faillock.
auth	required			pam_faillock.so preauth
auth	[success=1 default=ignore]	pam_unix.so nullok
auth	[default=die]			pam_faillock.so authfail
auth	sufficient			pam_faillock.so authsucc
auth	requisite			pam_deny.so
auth	required			pam_permit.so
auth	optional			pam_cap.so
'@

Write-PuppetFile 'modules/security/files/common-account' @'
# Gerido pelo Puppet (modulo security). Base: Ubuntu 22.04 + pam_faillock.
account	required			pam_faillock.so
account	[success=1 new_authtok_reqd=done default=ignore]	pam_unix.so
account	requisite			pam_deny.so
account	required			pam_permit.so
'@

Write-PuppetFile 'modules/security/files/common-password' @'
# Gerido pelo Puppet (modulo security). Base: Ubuntu 22.04 + pam_pwhistory.
password	requisite			pam_pwquality.so retry=3
password	required			pam_pwhistory.so remember=5 use_authtok enforce_for_root
password	[success=1 default=ignore]	pam_unix.so obscure use_authtok try_first_pass yescrypt
password	requisite			pam_deny.so
password	required			pam_permit.so
'@

Write-Host ""
Write-Host "Implementacao Puppet escrita em ansible\puppet. Proximo passo: .\prepare.ps1 (copia ansible/ para a VM app)."
