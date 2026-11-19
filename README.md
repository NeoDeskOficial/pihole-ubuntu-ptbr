<div align="center">

# Pi-hole no Ubuntu Server

**Instale o Pi-hole em servidor Ubuntu com um único comando, ou siga o passo a passo manual completo em português.**

![Licença MIT](https://img.shields.io/badge/licença-MIT-green)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20|%2024.04%20|%2026.04-E95420?logo=ubuntu&logoColor=white)
![Pi-hole](https://img.shields.io/badge/Pi--hole-v6-96060C)
![Idioma](https://img.shields.io/badge/idioma-PT--BR-blue)

</div>

---

## Sumário

- [Sobre o projeto](#sobre-o-projeto)
- [Método 1: Instalação rápida (uma linha)](#método-1-instalação-rápida-uma-linha)
- [O que o instalador faz](#o-que-o-instalador-faz)
- [Opções do instalador](#opções-do-instalador)
- [Requisitos](#requisitos)
- [Método 2: Instalação manual passo a passo](#método-2-instalação-manual-passo-a-passo)
- [Configurando a rede para usar o Pi-hole](#configurando-a-rede-para-usar-o-pi-hole)
- [Listas de bloqueio](#listas-de-bloqueio)
- [Comandos úteis](#comandos-úteis)
- [Atualização](#atualização)
- [Solução de problemas](#solução-de-problemas)
- [Desinstalação](#desinstalação)
- [Perguntas frequentes](#perguntas-frequentes)
- [Referências](#referências)
- [Contribuindo](#contribuindo)
- [Licença](#licença)

---

## Sobre o projeto

O [Pi-hole](https://pi-hole.net/) é um servidor DNS com filtragem. Quando um dispositivo tenta acessar um domínio de anúncio, rastreador ou malware que esteja nas listas de bloqueio, o Pi-hole responde com um endereço nulo e a requisição não se completa.

**Principais benefícios**

- Bloqueia anúncios e rastreadores em **todos os dispositivos da rede** (celulares, TVs, consoles, computadores), sem instalar nada neles.
- Reduz o consumo de banda e melhora o carregamento das páginas.
- Oferece um painel web com estatísticas das consultas DNS.
- Permite listas de bloqueio e liberação personalizadas.

Este repositório reúne:

| Arquivo | Descrição |
|---------|-----------|
| [`install.sh`](install.sh) | Instalador automatizado: atualiza o servidor, instala o Pi-hole e configura o firewall |
| `README.md` | Esta documentação, com instalação rápida e manual |
| [`LICENSE`](LICENSE) | Licença MIT |

---

## Método 1: Instalação rápida (uma linha)

Basta colar o comando abaixo, que já atualiza o servidor e instala tudo. Em um servidor Ubuntu com IP fixo, execute:

```bash
curl -fsSL https://raw.githubusercontent.com/NeoDeskOfocial/pihole-ubuntu-ptbr/main/install.sh | sudo bash
```

O assistente do Pi-hole faz perguntas durante a instalação (interface de rede, DNS upstream, etc.). Por isso, execute o comando em um terminal interativo, como uma sessão SSH.

### Prefere revisar o script antes de executar?

Executar scripts baixados da internet exige confiança na origem. Se quiser ler o código antes:

```bash
curl -fsSL https://raw.githubusercontent.com/NeoDeskOfocial/pihole-ubuntu-ptbr/main/install.sh -o install.sh
less install.sh
sudo bash install.sh
```

---

## O que o instalador faz

1. **Verifica o sistema:** versão do Ubuntu, memória RAM, espaço em disco e acesso à internet.
2. **Detecta a rede:** interface, endereço IP e avisa se o IP parece dinâmico (DHCP).
3. **Atualiza o servidor:** `apt update` e `apt upgrade` sem perguntas.
4. **Instala as dependências:** `curl`, `ca-certificates`, `iproute2`, `git` e `ufw`.
5. **Confere a porta 53:** impede a instalação se outro serviço de DNS estiver ocupando a porta.
6. **Instala o Pi-hole:** baixa o instalador oficial e o executa a partir de um arquivo, o que evita o travamento relatado no formato `curl | bash` no Ubuntu 26.04.
7. **Define a senha do painel web** (opcional, com confirmação).
8. **Configura o firewall UFW** (opcional, com confirmação), liberando SSH, DNS e o painel web somente para a sua rede local.
9. **Mostra um resumo final** com o endereço do painel e os próximos passos.

O script pede confirmação antes de qualquer ação mais sensível e encerra com mensagem clara se algo estiver errado.

---

## Opções do instalador

Passe opções com `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/NeoDeskOfocial/pihole-ubuntu-ptbr/main/install.sh | sudo bash -s -- --sem-upgrade
```

| Opção | Efeito |
|-------|--------|
| `--sem-upgrade` | Não atualiza os pacotes do sistema |
| `--sem-firewall` | Não configura o UFW |
| `--sim` | Responde "sim" às perguntas do script (o assistente do Pi-hole continua interativo) |
| `--ajuda` | Mostra a ajuda (ao executar o arquivo baixado) |

> **Atenção ao firewall:** o instalador libera o SSH somente para a sua rede local. Se você acessa o servidor por SSH de fora dessa rede, use `--sem-firewall` para não perder o acesso.

---

## Requisitos

| Item | Mínimo recomendado |
|------|--------------------|
| Sistema operacional | Ubuntu Server 22.04 LTS, 24.04 LTS ou 26.04 LTS |
| CPU | 1 núcleo |
| Memória RAM | 512 MB (1 GB recomendado) |
| Disco | 2 GB livres (10 GB recomendado para logs) |
| Rede | Endereço IP **fixo** na rede local |
| Acesso | Usuário com permissão `sudo` |

> O Pi-hole não deve ser instalado em um servidor que já use as portas 53 (DNS), 80 ou 443 (web) para outros serviços, a menos que você ajuste as portas.

### IP fixo

Os dispositivos usarão o IP do servidor como DNS, então ele não pode mudar. Há duas formas de garantir isso: configurar o IP fixo no próprio servidor (Netplan, descrito abaixo) ou reservar o IP no roteador (reserva DHCP por MAC). O ideal é fazer as duas.

**Configuração via Netplan**

Descubra a interface e o gateway:

```bash
ip -br a
ip route | grep default
ls /etc/netplan/
```

Edite o arquivo encontrado (o nome varia, por exemplo `00-installer-config.yaml` ou `50-cloud-init.yaml`):

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

Exemplo (ajuste interface e endereços para a sua rede):

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

Aplique com segurança:

```bash
sudo netplan try
```

Se a conexão continuar funcionando, confirme com **Enter**. O `netplan try` desfaz a alteração sozinho se você perder o acesso.

---

## Método 2: Instalação manual passo a passo

Prefere fazer cada etapa por conta própria? Siga abaixo. Aqui a instalação do Pi-hole usa o comando oficial do projeto: `curl -sSL https://install.pi-hole.net | bash`.

### 1. Preparar o servidor

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git ufw
sudo timedatectl set-timezone America/Sao_Paulo
```

### 2. Resolver conflito na porta 53 (se necessário)

O Ubuntu usa o `systemd-resolved`, que mantém um *stub resolver* em `127.0.0.53:53`. Verifique quem usa a porta:

```bash
sudo ss -tulpn | grep ':53 '
```

Se o instalador acusar erro de porta em uso ou o serviço `pihole-FTL` não iniciar, desative o *stub listener*:

```bash
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nDNSStubListener=no\n' | sudo tee /etc/systemd/resolved.conf.d/pihole.conf
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
sudo systemctl restart systemd-resolved
```

### 3. Instalar o Pi-hole

```bash
curl -sSL https://install.pi-hole.net | bash
```

Rode com seu usuário normal. O instalador pede a senha do `sudo` quando necessário.

> **Ubuntu 26.04:** há relatos de a instalação parecer travada com o comando acima. Se acontecer, interrompa com `Ctrl + C` e use o método em duas etapas, que faz a mesma instalação:
>
> ```bash
> curl -sSL https://install.pi-hole.net -o install.sh && sudo bash install.sh; rm install.sh
> ```

**Assistente de instalação**

1. **Aviso de requisitos:** confirme que o servidor tem IP fixo.
2. **Interface de rede:** selecione a interface principal (ex.: `ens18`).
3. **Provedor DNS upstream:** escolha para onde o Pi-hole encaminha as consultas não bloqueadas (Cloudflare, Google, Quad9 etc.).
4. **Lista de bloqueio padrão:** aceite a lista inicial.
5. **Registro de consultas:** recomendado manter ativado.
6. **Modo de privacidade:** escolha o nível de detalhe das estatísticas.

### 4. Definir a senha do painel

```bash
sudo pihole setpassword
```

Acesse `http://IP-DO-SERVIDOR/admin` no navegador (por exemplo, `http://192.168.0.10/admin`).

### 5. Configurar o firewall (UFW)

Libere apenas o necessário, **somente para a sua rede local** (ajuste `192.168.0.0/24`):

```bash
# SSH (libere antes de ativar o firewall para não perder o acesso)
sudo ufw allow from 192.168.0.0/24 to any port 22 proto tcp

# DNS
sudo ufw allow from 192.168.0.0/24 to any port 53

# Painel web
sudo ufw allow from 192.168.0.0/24 to any port 80 proto tcp
sudo ufw allow from 192.168.0.0/24 to any port 443 proto tcp

# Somente se o Pi-hole for o servidor DHCP da rede
# sudo ufw allow from 192.168.0.0/24 to any port 67 proto udp

sudo ufw enable
sudo ufw status verbose
```

> **Importante:** nunca exponha a porta 53 do Pi-hole para a internet. Um DNS aberto pode ser abusado em ataques de amplificação. Essas regras tratam apenas de tráfego de entrada, então o Pi-hole continua acessando normalmente o DNS upstream (como a Cloudflare).

---

## Configurando a rede para usar o Pi-hole

### Opção A: pelo roteador (recomendada)

1. Acesse o painel do roteador.
2. Localize as configurações de **DHCP / LAN**.
3. Defina o **DNS primário** como o IP do Pi-hole (ex.: `192.168.0.10`).
4. Deixe o **DNS secundário vazio**. Um DNS público no secundário faz parte das consultas escapar do bloqueio.
5. Renove a conexão nos dispositivos para pegar a nova configuração.

> Alguns roteadores de operadora não permitem alterar o DNS da LAN. Nesse caso, use a opção B, ou use o próprio Pi-hole como servidor DHCP (desativando o DHCP do roteador).

### Opção B: dispositivo por dispositivo

Configure manualmente o DNS de cada dispositivo para o IP do Pi-hole.

### Testando

Em um computador da rede:

```bash
nslookup doubleclick.net 192.168.0.10   # domínio de anúncio: deve retornar 0.0.0.0
nslookup google.com 192.168.0.10        # domínio normal: deve resolver
```

No painel, a aba **Query Log** mostra as consultas chegando e quais foram bloqueadas.

---

## Listas de bloqueio

No painel, abra **Adlists**, adicione a URL da lista e atualize o *gravity*. Pelo terminal:

```bash
sudo pihole -g
```

| Lista | URL |
|-------|-----|
| StevenBlack (padrão) | `https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts` |
| OISD | `https://big.oisd.nl` |
| HaGeZi Multi Pro | `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt` |

> Quanto mais listas, maior a chance de **falsos positivos** (sites legítimos bloqueados). Comece com poucas e amplie aos poucos.

Liberar ou bloquear um domínio manualmente:

```bash
sudo pihole allow exemplo.com
sudo pihole deny exemplo.com
```

---

## Comandos úteis

| Comando | Descrição |
|---------|-----------|
| `pihole status` | Mostra se o Pi-hole está ativo |
| `pihole -g` | Atualiza as listas de bloqueio (gravity) |
| `pihole -q dominio.com` | Mostra em quais listas um domínio está |
| `pihole -t` | Acompanha as consultas em tempo real |
| `pihole disable 5m` | Desativa o bloqueio por 5 minutos |
| `pihole enable` | Reativa o bloqueio |
| `pihole setpassword` | Define ou altera a senha do painel |
| `pihole -up` | Atualiza o Pi-hole |
| `pihole -d` | Gera log de depuração |
| `pihole -r` | Repara ou reconfigura a instalação |

Gerenciamento do serviço:

```bash
sudo systemctl status pihole-FTL
sudo systemctl restart pihole-FTL
```

---

## Atualização

```bash
sudo pihole -up
sudo apt update && sudo apt upgrade -y
```

---

## Solução de problemas

<details>
<summary><strong>A instalação parece travada (Ubuntu 26.04)</strong></summary>

Interrompa com `Ctrl + C` e use o instalador deste repositório (que já contorna o problema) ou o método em duas etapas:

```bash
curl -sSL https://install.pi-hole.net -o install.sh && sudo bash install.sh; rm install.sh
```
</details>

<details>
<summary><strong>O serviço <code>pihole-FTL</code> não inicia</strong></summary>

```bash
sudo systemctl status pihole-FTL
sudo journalctl -u pihole-FTL -n 50 --no-pager
sudo ss -tulpn | grep -E ':53 |:80 |:443 '
```

Normalmente é conflito de porta. Veja a seção sobre a [porta 53](#2-resolver-conflito-na-porta-53-se-necessário) ou verifique se outro servidor web usa as portas 80/443.
</details>

<details>
<summary><strong>Sem internet depois de configurar o DNS</strong></summary>

- Verifique se o Pi-hole está ativo: `pihole status`
- Teste no próprio servidor: `dig google.com @127.0.0.1`
- Confirme o DNS upstream em **Settings → DNS** no painel
- Verifique o firewall: `sudo ufw status`
</details>

<details>
<summary><strong>Um site legítimo foi bloqueado</strong></summary>

```bash
pihole -q dominio.com          # descobre qual lista bloqueou
sudo pihole allow dominio.com  # libera o domínio
```
</details>

<details>
<summary><strong>Os anúncios ainda aparecem</strong></summary>

- O dispositivo pode estar usando outro DNS (DNS privado do Android, DNS sobre HTTPS no navegador ou VPN).
- Anúncios servidos pelo mesmo domínio do conteúdo (como no YouTube e em aplicativos) não podem ser bloqueados por DNS.
</details>

<details>
<summary><strong>Perdi o acesso SSH depois do firewall</strong></summary>

O firewall libera o SSH apenas para a rede local. Acesse o servidor pelo console físico ou pelo painel da virtualização e libere seu IP:

```bash
sudo ufw allow from SEU.IP.AQUI to any port 22 proto tcp
```
</details>

Para qualquer outro problema, gere um log de depuração com `sudo pihole -d` e consulte o [fórum oficial](https://discourse.pi-hole.net/).

---

## Desinstalação

```bash
sudo pihole uninstall
```

Depois, restaure o DNS do roteador e dos dispositivos para o padrão e reverta o `systemd-resolved`, se tiver alterado:

```bash
sudo rm -f /etc/systemd/resolved.conf.d/pihole.conf
sudo systemctl restart systemd-resolved
```

---

## Perguntas frequentes

**O Pi-hole bloqueia anúncios do YouTube?**
Em geral, não. Os anúncios do YouTube são entregues pelos mesmos domínios dos vídeos, e o bloqueio por DNS não consegue separá-los.

**Posso instalar em Raspberry Pi, VM ou Docker?**
Sim, o Pi-hole funciona em todos. Este guia e o instalador foram feitos para Ubuntu Server (físico ou VM).

**Preciso deixar o servidor ligado o tempo todo?**
Sim. Se o Pi-hole estiver desligado e o DNS da rede apontar para ele, os dispositivos ficam sem resolver nomes.

**O instalador funciona em Debian?**
O Pi-hole oficialmente suporta Debian, e o script pede confirmação para continuar, mas os testes deste projeto foram feitos para Ubuntu.

---

## Referências

- Site oficial: <https://pi-hole.net/>
- Documentação: <https://docs.pi-hole.net/>
- Repositório do Pi-hole: <https://github.com/pi-hole/pi-hole>
- Fórum da comunidade: <https://discourse.pi-hole.net/>

---

## Contribuindo

Encontrou um erro ou quer melhorar o guia ou o instalador? Abra uma *issue* ou envie um *pull request*. Ao testar o instalador em outra versão do Ubuntu, conte nos comentários o resultado.

## Licença

Distribuído sob a licença [MIT](LICENSE).

> Este projeto não é afiliado ao Pi-hole. Pi-hole é uma marca de seus respectivos mantenedores.
