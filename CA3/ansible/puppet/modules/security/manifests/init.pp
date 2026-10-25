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
