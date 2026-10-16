# CA2: Infraestrutura Multi-Tier com Vagrant

**Disciplina:** COGSI (Configuração de Sistemas)  
**Data de Conclusão:** 16 de Outubro de 2026  
**Equipa:** Luiz Afonso (Parte 1) + João Paulo (Parte 2)

---

## Sumário

Este assignment implementa uma infraestrutura multi-tier com 3 máquinas virtuais:
- **VM `db`**: H2 Database (modo servidor, TCP porta 9092)
- **VM `app`**: Bookstore Spring Boot 3.3.0 com Gradle 8.8
- **VM `proxy`**: Nginx reverse proxy (porta 80)

Demonstra isolamento de camadas, comunicação inter-VM via rede privada, persistência com H2 servidor, firewall restritivo, chaves SSH personalizadas, e acesso centralizado através de proxy.

---

## Requisitos Atendidos

### Parte 1 (Semana 1 - Luiz)
- VM única com Vagrant + VirtualBox
- JDK 17, Maven, Gradle via provisioning
- Clone do repositório, build e execução (Bookstore + Chat)
- H2 em arquivo com pasta sincronizada
- Serviços systemd
- Persistência de dados verificada
- Tag `ca2-part1` criada

### Parte 2 (Semana 2 - João)
- Múltiplas VMs (`db`, `app`, `proxy`)
- H2 em modo servidor (TCP)
- Rede privada 192.168.56.0/24
- Chaves SSH próprias por VM (Ed25519)
- Health check antes de iniciar Bookstore
- Firewall (ufw) na VM `db`
- Nginx reverse proxy
- Topologia documentada
- Tag `ca2-part2` criada

---

## Topologia de Rede

```
Windows Host (192.168.56.1)
        │
        ├─→ Nginx Proxy (192.168.56.20:80)
        │       │
        ├─→ Bookstore (192.168.56.10:8080)
        │       │
        └─→ H2 Database (192.168.56.30:9092)

Rede: host-only VirtualBox (192.168.56.0/24)
Firewall: db bloqueia 9092 de tudo exceto app
```

---

## Como Executar

### Setup
```powershell
cd CA2/Part2
vagrant up            # ~60 minutos primeira execução

# Verificar
vagrant status        # Todas VMs: running
curl http://localhost/books           # Via proxy (HTTP 200)
curl http://localhost:8080/books      # Direto (HTTP 200)
```

### Resultado Esperado
```json
[
  {"id":1,"title":"Clean Code","author":"Robert C. Martin","price":30.0},
  {"id":2,"title":"Effective Java","author":"Joshua Bloch","price":40.0}
]
```

---

## Componentes

### H2 Database (VM `db`)
- JDK 17, H2 2.2.224
- Serviço systemd: `h2-server.service`
- Porta: 9092 (TCP)
- Firewall: Aceita apenas de 192.168.56.10 (app)

### Bookstore (VM `app`)
- Spring Boot 3.3.0, Gradle 8.8
- Porta: 8080
- Conexão H2: JDBC TCP (192.168.56.30:9092)
- Health check: Aguarda porta 9092 antes de iniciar

### Nginx (VM `proxy`)
- Porta: 80
- Upstream: 192.168.56.10:8080
- Headers: X-Real-IP, X-Forwarded-For, X-Forwarded-Proto

---

## Problemas Resolvidos

| Problema | Causa | Solução |
|----------|-------|---------|
| JAR não encontrado | `app.jar` vs `app-1.0.0.jar` | Usar nome correto no script |
| `./gradlew` Permission denied | Git Windows não preserva permissões | `chmod +x ./gradlew` |
| CRLF vs LF em scripts | Git auto-converte | `.gitattributes: *.sh text eol=lf` |
| Bookstore falha ao iniciar | H2 não pronto | Health check com netcat |

---

## Solução Alternativa: Terraform + Libvirt

Análise (design-only, não implementado):

| Aspecto | Vagrant | Terraform+Libvirt |
|---------|---------|-------------------|
| Portabilidade | Excelente | Boa (melhor em Linux) |
| Facilidade | Excelente | Boa |
| Performance | Boa | Excelente (KVM nativo) |
| Infraestrutura como Código | Parcial | Completo |
| Scaling | Manual | Automático |

**Desenho HCL2 (exemplo):**
```hcl
variable "vms" {
  default = {
    db    = { memory = 1024, cpus = 1 }
    app   = { memory = 2048, cpus = 2 }
    proxy = { memory = 512, cpus = 1 }
  }
}

resource "libvirt_network" "ca2" {
  name = "ca2-network"
  addresses = ["192.168.56.0/24"]
}

resource "libvirt_domain" "vm" {
  for_each = var.vms
  name     = "ca2-${each.key}"
  memory   = each.value.memory
  vcpu     = each.value.cpus
}
```

**Conclusão:** Terraform seria melhor em produção/multi-cloud. Vagrant é ideal para este assignment (simplicidade, portabilidade).

---

## Autoavaliação

| Membro | Contribuição | % |
|--------|-------------|---|
| **Luiz (Parte 1)** | VM única, H2 arquivo, systemd, provisionadores | 50% |
| **João (Parte 2)** | Multi-VM, H2 servidor, networking, firewall, SSH, proxy, debugging | 50% |

---

## Referências

- [Vagrant](https://www.vagrantup.com/docs)
- [H2 Database](https://h2database.com)
- [Spring Boot 3.3.0](https://spring.io/projects/spring-boot)
- [Nginx](https://nginx.org/en/docs/)
- [Terraform Libvirt](https://registry.terraform.io/providers/dmacvicar/libvirt/latest)

---

**Status:** COMPLETO E TESTADO  
**Data:** 16 de Outubro de 2026, 02:50 UTC  
**Tags:** `ca2-part1`, `ca2-part2`
