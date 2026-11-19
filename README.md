# Instalação do Pi-hole em Servidor Ubuntu

Guia completo, em português, para instalar e configurar o [Pi-hole](https://pi-hole.net/) em um servidor Ubuntu (22.04 LTS, 24.04 LTS e 26.04 LTS), funcionando como bloqueador de anúncios e rastreadores em nível de DNS para toda a sua rede.

> **Versão de referência:** Pi-hole v6.x. Os comandos e caminhos de arquivos deste guia seguem essa versão.

---

## Sumário

1. [O que é o Pi-hole](#1-o-que-é-o-pi-hole)
2. [Requisitos](#2-requisitos)
3. [Preparação do servidor](#3-preparação-do-servidor)
4. [Configuração de IP fixo](#4-configuração-de-ip-fixo)
5. [Resolvendo conflito na porta 53 (se necessário)](#5-resolvendo-conflito-na-porta-53-se-necessário)
6. [Instalação do Pi-hole](#6-instalação-do-pi-hole)
7. [Acesso à interface web e senha](#7-acesso-à-interface-web-e-senha)
8. [Configuração do firewall (UFW)](#8-configuração-do-firewall-ufw)
9. [Apontando a rede para o Pi-hole](#9-apontando-a-rede-para-o-pi-hole)
10. [Listas de bloqueio (adlists)](#10-listas-de-bloqueio-adlists)
11. [Comandos úteis](#11-comandos-úteis)
12. [Atualização](#12-atualização)
13. [Solução de problemas](#13-solução-de-problemas)
14. [Desinstalação](#14-desinstalação)
15. [Referências](#15-referências)

---

## 1. O que é o Pi-hole

O Pi-hole é um servidor DNS com filtragem. Quando um dispositivo da rede tenta acessar um domínio de anúncio, rastreador ou malware que esteja nas listas de bloqueio, o Pi-hole responde com um endereço nulo e a requisição não é concluída.

**Vantagens:**

- Bloqueia anúncios em todos os dispositivos da rede (celulares, TVs, consoles, computadores), sem instalar nada neles.
- Reduz consumo de banda e melhora o tempo de carregamento de páginas.
- Oferece painel com estatísticas de consultas DNS.
- Permite listas de bloqueio e liberação personalizadas.

## 2. Requisitos

| Item | Mínimo recomendado |
|------|--------------------|
| Sistema operacional | Ubuntu Server 22.04 LTS, 24.04 LTS ou 26.04 LTS |
| CPU | 1 núcleo |
| Memória RAM | 512 MB (1 GB recomendado) |
| Disco | 2 GB livres (10 GB recomendado para logs) |
| Rede | Endereço IP **fixo** na rede local |
| Acesso | Usuário com permissão `sudo` |

> O Pi-hole **não** deve ser instalado em um servidor que já utilize as portas 53 (DNS), 80 ou 443 (web) para outros serviços, a menos que você ajuste as portas.

## 3. Preparação do servidor

Atualize o sistema e instale utilitários básicos:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git ufw
```

Confira a versão do Ubuntu:

```bash
lsb_release -a
```

Defina o fuso horário (importante para os horários nos logs e estatísticas):

```bash
sudo timedatectl set-timezone America/Sao_Paulo
timedatectl
```

## 4. Configuração de IP fixo

O Pi-hole precisa de um IP que não mude, pois os dispositivos da rede vão usá-lo como servidor DNS.

### 4.1 Descubra o nome da interface e as informações atuais

```bash
ip -br a
ip route | grep default
```

Anote:

- Nome da interface (ex.: `eth0`, `ens18`, `enp3s0`)
- Gateway (IP do roteador, ex.: `192.168.0.1`)
- Faixa de rede (ex.: `192.168.0.0/24`)

### 4.2 Configure via Netplan

Liste os arquivos existentes:

```bash
ls /etc/netplan/
```

Edite o arquivo encontrado (o nome pode variar, por exemplo `00-installer-config.yaml` ou `50-cloud-init.yaml`):

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

Exemplo de configuração (ajuste interface e endereços para a sua rede):

```yaml
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: false
      addresses:
        - 192.168.0.10/24
      routes:
        - to: default
          via: 192.168.0.1
      nameservers:
        addresses:
          - 1.1.1.1
          - 1.0.0.1
```

Aplique:

```bash
sudo netplan try
```

Se a conexão continuar funcionando, confirme pressionando **Enter**. Depois valide:

```bash
ip -br a
ping -c 3 google.com
```

> **Dica:** também é boa prática reservar esse IP no roteador (reserva DHCP por MAC) para evitar conflitos.

## 5. Resolvendo conflito na porta 53 (se necessário)

O Ubuntu usa o `systemd-resolved`, que mantém um *stub resolver* em `127.0.0.53:53`. Em alguns casos isso causa conflito com o Pi-hole. Verifique quem está usando a porta 53:

```bash
sudo ss -tulpn | grep ':53 '
```

Se o instalador acusar erro de porta em uso ou o serviço `pihole-FTL` não iniciar, desative o *stub listener*:

```bash
sudo mkdir -p /etc/systemd/resolved.conf.d
sudo nano /etc/systemd/resolved.conf.d/pihole.conf
```

Conteúdo:

```ini
[Resolve]
DNSStubListener=no
```

Atualize o link do `resolv.conf` e reinicie o serviço:

```bash
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved
```

Confirme que a porta 53 ficou livre:

```bash
sudo ss -tulpn | grep ':53 '
```

## 6. Instalação do Pi-hole

### 6.1 Instalador oficial (instalação automatizada)

```bash
curl -sSL https://install.pi-hole.net | bash
```

Rode o comando com seu usuário normal. O instalador avisa que precisa de privilégios elevados e pede a senha do `sudo` quando necessário.

> **Segurança:** esse comando executa um script baixado da internet. Se quiser revisar o conteúdo antes de executar, baixe o arquivo e leia com `curl -sSL https://install.pi-hole.net -o basic-install.sh && less basic-install.sh`.

> **Ubuntu 26.04:** há relatos de a instalação parecer travada ao usar o comando acima. Se isso acontecer, interrompa com `Ctrl + C` e use o método em duas etapas, que faz exatamente a mesma instalação:
>
> ```bash
> curl -sSL https://install.pi-hole.net -o install.sh && sudo bash install.sh; rm install.sh
> ```

### 6.2 Passo a passo do assistente

Durante a instalação, o assistente (tela azul) fará algumas perguntas:

1. **Aviso de requisitos** – confirme que o servidor possui IP fixo.
2. **Interface de rede** – selecione a interface principal (ex.: `ens18`).
3. **Provedor DNS upstream** – escolha para onde o Pi-hole encaminhará as consultas não bloqueadas (Cloudflare, Google, Quad9, OpenDNS etc.).
4. **Lista de bloqueio padrão** – aceite a lista inicial (StevenBlack).
5. **Registro de consultas (logging)** – recomendado manter ativado.
6. **Modo de privacidade** – escolha o nível de detalhe das estatísticas (o padrão mostra tudo).

Ao final, o assistente exibirá o endereço da interface web. Na v6 a senha do administrador é definida por você (veja a próxima seção).

## 7. Acesso à interface web e senha

Defina (ou redefina) a senha do painel:

```bash
sudo pihole setpassword
```

Acesse pelo navegador:

```
http://192.168.0.10/admin
```

(substitua pelo IP do seu servidor). Entre com a senha definida.

## 8. Configuração do firewall (UFW)

Libere apenas o necessário, **somente para a sua rede local** (ajuste `192.168.0.0/24` para a sua faixa):

```bash
# SSH (não esqueça, para não perder o acesso ao servidor)
sudo ufw allow from 192.168.0.0/24 to any port 22 proto tcp

# DNS
sudo ufw allow from 192.168.0.0/24 to any port 53 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 53 proto udp

# Interface web (HTTP e HTTPS)
sudo ufw allow from 192.168.0.0/24 to any port 80 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 443 proto tcp

# Somente se for usar o Pi-hole como servidor DHCP
# sudo ufw allow from 192.168.0.0/24 to any port 67 proto udp

sudo ufw enable
sudo ufw status verbose
```

> **Atenção:** nunca exponha a porta 53 do Pi-hole para a internet. Um DNS aberto pode ser abusado em ataques de amplificação.

## 9. Apontando a rede para o Pi-hole

Há duas formas principais de fazer os dispositivos usarem o Pi-hole.

### Opção A – Pelo roteador (recomendada)

1. Acesse o painel do roteador.
2. Localize as configurações de **DHCP / LAN**.
3. Defina o **DNS primário** como o IP do Pi-hole (ex.: `192.168.0.10`).
4. Deixe o DNS secundário **vazio** (ou use outro Pi-hole). Se colocar um DNS público, parte das consultas pode escapar do bloqueio.
5. Reinicie a conexão nos dispositivos para renovar o DHCP.

> Alguns roteadores de operadoras não permitem alterar o DNS da LAN. Nesse caso, use a opção B ou o próprio Pi-hole como servidor DHCP (desativando o DHCP do roteador).

### Opção B – Dispositivo por dispositivo

Configure manualmente o DNS de cada dispositivo para o IP do Pi-hole.

### Testando

Em um computador cliente:

```bash
nslookup doubleclick.net 192.168.0.10
```

Um domínio bloqueado deve retornar `0.0.0.0` (ou resposta nula). Teste também um domínio normal:

```bash
nslookup google.com 192.168.0.10
```

Você também pode conferir no painel em **Query Log** se as consultas estão chegando.

## 10. Listas de bloqueio (adlists)

No painel: **Adlists** → adicione a URL da lista → **Add** → depois atualize o gravity.

Via terminal, após adicionar listas:

```bash
sudo pihole -g
```

Algumas listas populares:

| Lista | URL |
|-------|-----|
| StevenBlack (padrão) | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` |
| OISD (completa) | `https://big.oisd.nl` |
| HaGeZi Multi Pro | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt` |

> Cuidado com excesso de listas: quanto mais listas, maior a chance de **falsos positivos** (sites legítimos bloqueados). Comece com poucas e vá ampliando.

### Liberando ou bloqueando domínios manualmente

```bash
sudo pihole allow exemplo.com     # libera um domínio
sudo pihole deny exemplo.com      # bloqueia um domínio
```

## 11. Comandos úteis

| Comando | Descrição |
|---------|-----------|
| `pihole status` | Mostra se o Pi-hole está ativo |
| `pihole -g` | Atualiza as listas de bloqueio (gravity) |
| `pihole -q dominio.com` | Verifica em quais listas um domínio está |
| `pihole -t` | Acompanha o log de consultas em tempo real |
| `pihole disable 5m` | Desativa o bloqueio por 5 minutos |
| `pihole enable` | Reativa o bloqueio |
| `pihole setpassword` | Define/altera a senha do painel |
| `pihole -up` | Atualiza o Pi-hole |
| `pihole -d` | Gera log de depuração |
| `pihole -r` | Reparar / reconfigurar a instalação |

Gerenciamento do serviço:

```bash
sudo systemctl status pihole-FTL
sudo systemctl restart pihole-FTL
```

## 12. Atualização

```bash
sudo pihole -up
```

Mantenha também o Ubuntu atualizado:

```bash
sudo apt update && sudo apt upgrade -y
```

## 13. Solução de problemas

### A instalação parece travada (Ubuntu 26.04)

Interrompa com `Ctrl + C` e use o método em duas etapas descrito na [seção 6.1](#61-instalador-oficial-instalação-automatizada).

### O serviço `pihole-FTL` não inicia

```bash
sudo systemctl status pihole-FTL
sudo journalctl -u pihole-FTL -n 50 --no-pager
sudo ss -tulpn | grep -E ':53 |:80 |:443 '
```

Normalmente é conflito de porta. Veja a [seção 5](#5-resolvendo-conflito-na-porta-53-se-necessário) ou o caso de outro servidor web ocupando as portas 80/443.

### Sem acesso à internet depois de configurar o DNS

- Verifique se o Pi-hole está ativo: `pihole status`.
- Teste a resolução no próprio servidor: `dig google.com @127.0.0.1`.
- Confirme o DNS upstream em **Settings → DNS** no painel.
- Verifique o firewall: `sudo ufw status`.

### Site legítimo bloqueado

1. Descubra qual lista bloqueou: `pihole -q dominio.com`.
2. Libere o domínio: `sudo pihole allow dominio.com`.

### Anúncios ainda aparecem

- O dispositivo pode estar usando outro DNS (DNS privado do Android, DNS sobre HTTPS no navegador, VPN).
- Alguns anúncios (como os do YouTube e de aplicativos) vêm do mesmo domínio do conteúdo e não podem ser bloqueados por DNS.

### Gerar log de depuração

```bash
sudo pihole -d
```

## 14. Desinstalação

```bash
sudo pihole uninstall
```

Depois, restaure o DNS dos dispositivos/roteador para o padrão e, se tiver alterado, reverta a configuração do `systemd-resolved`:

```bash
sudo rm /etc/systemd/resolved.conf.d/pihole.conf
sudo systemctl restart systemd-resolved
```

## 15. Referências

- Site oficial: <https://pi-hole.net/>
- Documentação: <https://docs.pi-hole.net/>
- Repositório: <https://github.com/pi-hole/pi-hole>
- Fórum da comunidade: <https://discourse.pi-hole.net/>

---

## Contribuindo

Encontrou algum erro ou quer melhorar este guia? Abra uma *issue* ou envie um *pull request*.

## Licença

Este guia é distribuído sob a licença [MIT](LICENSE).
