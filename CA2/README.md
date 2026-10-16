# CA2: Infraestrutura Multi-Tier com Vagrant e H2 Database

**Disciplina:** COGSI (Configuração de Sistemas)  
**Data de Conclusão:** 16 de Outubro de 2026  
**Equipa:** Luiz Afonso (Parte 1) + João Paulo (Parte 2)

---

## 📋 Sumário Executivo

Este assignment implementa uma infraestrutura multi-tier com **3 máquinas virtuais** usando Vagrant e VirtualBox:

1. **VM `db`**: H2 Database em modo servidor (TCP, porta 9092)
2. **VM `app`**: Bookstore (Spring Boot 3.3.0) com Gradle 8.8
3. **VM `proxy`**: Nginx como reverse proxy (porta 80)

A solução demonstra isolamento de camadas, comunicação entre VMs via rede privada (192.168.56.0/24), persistência de dados com H2 servidor, firewall restritivo (ufw), chaves SSH personalizadas, e acesso seguro através de um proxy reverso.

---

## 🎯 Requisitos Atendidos

### Parte 1 (Semana 1 - Luiz)
- ✅ VM única com Vagrant + VirtualBox
- ✅ JDK 17, Maven, Gradle instalados via provisioning
- ✅ Clone do repositório dentro da VM  
- ✅ Build e execução da Bookstore (Gradle 8.8) + demo Chat (Gradle 9.4.0)
- ✅ H2 em arquivo com pasta sincronizada
- ✅ Serviços systemd para as aplicações
- ✅ Verificação de persistência de dados
- ✅ Tag `ca2-part1` criada

### Parte 2 (Semana 2 - João)
- ✅ **Múltiplas VMs** (`db`, `app`, `proxy`)
- ✅ **H2 em modo servidor** (TCP, porta 9092)
- ✅ **Rede privada** (192.168.56.0/24) entre VMs
- ✅ **Chaves SSH próprias** por VM (Ed25519)
- ✅ **Health check** antes de iniciar Bookstore
- ✅ **Firewall (ufw)** na VM `db`
- ✅ **Nginx reverse proxy** na VM `proxy`
- ✅ **Topologia documentada**
- ✅ **Tag `ca2-part2`** criada

---

## 🏗️ Topologia de Rede

```
Windows Host (192.168.56.1)
        │
        ├─► Nginx Proxy (192.168.56.20:80)
        │       │
        │       ▼
        ├─► Bookstore App (192.168.56.10:8080)
        │       │
        │       ▼
        └─► H2 Database (192.168.56.30:9092)
                (firewall: bloqueado de tudo exceto app)

Rede: host-only VirtualBox (192.168.56.0/24)
Acesso do Host:
  - Via Proxy: curl http://localhost/books
  - Direto (app): curl http://localhost:8080/books
```

---

## 🚀 Como Executar

### Pré-requisitos
- VirtualBox 7.2.18+
- Vagrant 2.4.9
- Git 2.51.0+
- PowerShell 5.1+

### Setup
```powershell
cd CA2/Part2
vagrant up            # ~60 min primeira vez

# Verificar
vagrant status        # Todas as 3 VMs devem estar "running"
curl http://localhost/books  # Via proxy (HTTP 200)
curl http://localhost:8080/books  # Direto (HTTP 200)
```

---

## 🔧 Componentes Principais

### 1. H2 Database (VM `db`)

**Instalação:**
- JDK 17 (headless)
- H2 2.2.224 (downloaded from Maven Central)
- Serviço systemd: `h2-server.service`

**Porta:** 9092 (TCP)  
**Firewall:** Apenas aceita conexões de 192.168.56.10 (app)

**Comando:**
```bash
java -cp h2-2.2.224.jar org.h2.tools.Server \
  -tcp -tcpAllowOthers -tcpPort 9092 \
  -baseDir /var/lib/h2 -ifNotExists
```

### 2. Bookstore App (VM `app`)

**Tecnologia:** Spring Boot 3.3.0 + Gradle 8.8  
**Clone:** `CA1/week2` (Gradle wrapper)  
**Porta:** 8080  
**Banco:** H2 via JDBC TCP (192.168.56.30:9092)

**Health Check:** Aguarda porta 9092 antes de iniciar
```bash
while ! nc -z 192.168.56.30 9092; do sleep 2; done
```

**Configuração:**
```properties
spring.datasource.url=jdbc:h2:tcp://192.168.56.30:9092/bookstore;DB_CLOSE_ON_EXIT=FALSE
spring.datasource.username=sa
spring.datasource.password=
spring.jpa.hibernate.ddl-auto=update
```

### 3. Nginx Reverse Proxy (VM `proxy`)

**Porta:** 80  
**Upstream:** 192.168.56.10:8080

**Configuração:**
```nginx
location / {
    proxy_pass http://192.168.56.10:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
}
```

---

## ⚠️ Problemas Encontrados e Soluções

| Problema | Causa | Solução |
|----------|-------|---------|
| JAR não encontrado | `app.jar` vs `app-1.0.0.jar` | Atualizar script com nome correto |
| `./gradlew` Permission denied | Git Windows não preserva permissões | Adicionar `chmod +x ./gradlew` |
| CRLF vs LF em scripts | Git auto-converte no Windows | `.gitattributes: *.sh text eol=lf` |
| Guest Additions 6.0.0 vs VirtualBox 7.2 | Versões desacopladas | Não bloqueia; funciona |
| Bookstore falha ao iniciar | H2 não estava pronto | Health check (netcat) resolveu |

---

## 🔄 Solução Alternativa: Terraform + Libvirt

### Análise Comparativa

| Aspecto | Vagrant | Terraform+Libvirt |
|---------|---------|-------------------|
| Portabilidade | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Performance | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Facilidade | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Infraestrutura como Código | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| Scaling | Manual | Automático |

### Desenho Terraform (HCL2)

```hcl
# Definir VMs
variable "vms" {
  default = {
    db    = { memory = 1024, cpus = 1 }
    app   = { memory = 2048, cpus = 2 }
    proxy = { memory = 512, cpus = 1 }
  }
}

# Criar rede privada
resource "libvirt_network" "ca2" {
  name = "ca2-network"
  addresses = ["192.168.56.0/24"]
}

# Criar VMs
resource "libvirt_domain" "vm" {
  for_each = var.vms
  
  name     = "ca2-${each.key}"
  memory   = each.value.memory
  vcpu     = each.value.cpus
  
  network_interface {
    network_name = libvirt_network.ca2.name
  }
}
```

**Vantagens vs Vagrant:**
- ✅ Melhor para scaling
- ✅ Estado persistente (`.tfstate`)
- ✅ Performance nativa em Linux (KVM)
- ✅ Integração com CI/CD

**Conclusão:** Terraform seria melhor em produção, mas Vagrant é ideal para este assignment (simplicidade, portabilidade).

---

## 📊 Autoavaliação

| Membro | Contribuição | % | Justificativa |
|--------|-------------|---|-|
| **Luiz (Parte 1)** | VM única, H2 arquivo, provisionadores, systemd | 50 | Base sólida; troubleshooting Windows |
| **João (Parte 2)** | Multi-VM, H2 servidor, networking, firewall, proxy, SSH keys, debugging | 50 | Arquitetura realista; resolveu permissões e nomes JAR |

---

## 📚 Referências

- [Vagrant Docs](https://www.vagrantup.com/docs)
- [H2 Database](https://h2database.com)
- [Spring Boot 3.3.0](https://spring.io/projects/spring-boot)
- [Nginx](https://nginx.org/en/docs/)
- [Terraform Libvirt](https://registry.terraform.io/providers/dmacvicar/libvirt/latest)

---

**Status:** ✅ **COMPLETO E TESTADO**  
**Data:** 16 de Outubro de 2026, 02:42 UTC  
**Tags:** `ca2-part1`, `ca2-part2`
