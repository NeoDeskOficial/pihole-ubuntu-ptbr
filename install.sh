#!/usr/bin/env bash
# ==============================================================================
#  Instalador automatizado do Pi-hole para Ubuntu Server
#
#  O que faz:
#    1. Verifica o sistema, a conexão e as portas necessárias
#    2. Atualiza o servidor (apt update + upgrade)
#    3. Instala as dependências
#    4. Executa o instalador oficial do Pi-hole
#    5. Define a senha do painel web
#    6. Configura o firewall UFW (opcional)
#
#  Uso (uma linha):
#    curl -fsSL https://raw.githubusercontent.com/SEU-USUARIO/pihole-ubuntu-ptbr/main/install.sh | sudo bash
#
#  Opções (use com: ... | sudo bash -s -- OPÇÃO):
#    --sem-upgrade    não atualiza os pacotes do sistema
#    --sem-firewall   não configura o UFW
#    --sim            responde "sim" às perguntas deste script
#    --ajuda          mostra esta ajuda
#
#  Licença: MIT
# ==============================================================================

set -Eeuo pipefail

readonly VERSAO_SCRIPT="1.0.0"
readonly PIHOLE_INSTALL_URL="https://install.pi-hole.net"

# ----------------------------- Opções e estado --------------------------------
FAZER_UPGRADE=1
CONFIGURAR_FIREWALL=1
ASSUMIR_SIM=0
TEM_TTY=0
TMP_INSTALADOR=""

# --------------------------------- Cores --------------------------------------
if [[ -t 1 ]]; then
  VERMELHO=$'\033[0;31m'; VERDE=$'\033[0;32m'; AMARELO=$'\033[0;33m'
  AZUL=$'\033[0;34m'; NEGRITO=$'\033[1m'; RESET=$'\033[0m'
else
  VERMELHO=""; VERDE=""; AMARELO=""; AZUL=""; NEGRITO=""; RESET=""
fi

info()  { printf '%s[i]%s %s\n' "$AZUL" "$RESET" "$*"; }
ok()    { printf '%s[✓]%s %s\n' "$VERDE" "$RESET" "$*"; }
aviso() { printf '%s[!]%s %s\n' "$AMARELO" "$RESET" "$*"; }
erro()  { printf '%s[✗]%s %s\n' "$VERMELHO" "$RESET" "$*" >&2; }
titulo() { printf '\n%s== %s ==%s\n' "$NEGRITO" "$*" "$RESET"; }

limpar() {
  [[ -n "$TMP_INSTALADOR" && -f "$TMP_INSTALADOR" ]] && rm -f "$TMP_INSTALADOR"
  return 0
}
trap limpar EXIT
trap 'erro "O script parou na linha $LINENO. Verifique a mensagem acima."' ERR

mostrar_ajuda() {
  sed -n '2,24p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//' || true
}

# ------------------------------ Argumentos ------------------------------------
for arg in "$@"; do
  case "$arg" in
    --sem-upgrade)  FAZER_UPGRADE=0 ;;
    --sem-firewall) CONFIGURAR_FIREWALL=0 ;;
    --sim)          ASSUMIR_SIM=1 ;;
    --ajuda|-h|--help) mostrar_ajuda; exit 0 ;;
    *) erro "Opção desconhecida: $arg (use --ajuda)"; exit 1 ;;
  esac
done

# --------------------------- Funções auxiliares -------------------------------
perguntar() {
  # perguntar "Texto" [S|N]  -> retorna 0 para sim, 1 para não
  local texto="$1" padrao="${2:-S}" resposta dica
  if [[ "$padrao" == "S" ]]; then dica="[S/n]"; else dica="[s/N]"; fi

  if (( ASSUMIR_SIM )) || (( ! TEM_TTY )); then
    [[ "$padrao" == "S" ]] || (( ASSUMIR_SIM ))
    return
  fi

  read -r -p "${AZUL}[?]${RESET} ${texto} ${dica} " resposta </dev/tty || resposta=""
  resposta="${resposta:-$padrao}"
  [[ "$resposta" =~ ^[SsYy] ]]
}

# ------------------------------- Verificações ---------------------------------
verificar_root() {
  if [[ $EUID -eq 0 ]]; then
    return
  fi
  if command -v sudo >/dev/null 2>&1 && [[ -f "${BASH_SOURCE[0]:-}" ]]; then
    exec sudo -E bash "${BASH_SOURCE[0]}" "$@"
  fi
  erro "Execute como root. Exemplo: curl -fsSL <URL>/install.sh | sudo bash"
  exit 1
}

verificar_terminal() {
  if [[ -r /dev/tty ]] && : </dev/tty 2>/dev/null; then
    TEM_TTY=1
  fi
  if (( ! TEM_TTY )); then
    erro "É necessário um terminal interativo: o assistente do Pi-hole faz perguntas durante a instalação."
    erro "Conecte-se por SSH ou abra um terminal e execute novamente."
    exit 1
  fi
}

verificar_sistema() {
  titulo "Verificando o sistema"

  if [[ ! -r /etc/os-release ]]; then
    erro "Não foi possível identificar o sistema operacional."
    exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release

  info "Sistema detectado: ${PRETTY_NAME:-desconhecido}"

  case "${ID:-}" in
    ubuntu)
      case "${VERSION_ID:-}" in
        22.04|24.04|26.04) ok "Versão do Ubuntu compatível." ;;
        *)
          aviso "Versão ${VERSION_ID:-?} não está na lista testada (22.04, 24.04 e 26.04)."
          perguntar "Deseja continuar mesmo assim?" N || exit 1
          ;;
      esac
      ;;
    debian)
      aviso "Este script foi pensado para Ubuntu. Debian costuma funcionar, mas não foi testado."
      perguntar "Deseja continuar mesmo assim?" N || exit 1
      ;;
    *)
      erro "Sistema não suportado: ${ID:-desconhecido}. Use Ubuntu Server."
      exit 1
      ;;
  esac

  if ! command -v apt-get >/dev/null 2>&1; then
    erro "O gerenciador de pacotes apt não foi encontrado."
    exit 1
  fi

  local ram_mb
  ram_mb=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
  if (( ram_mb < 400 )); then
    aviso "Pouca memória RAM detectada (${ram_mb} MB). O recomendado é 512 MB ou mais."
  else
    ok "Memória RAM: ${ram_mb} MB."
  fi

  local livre_mb
  livre_mb=$(df -Pm / | awk 'NR==2 {print $4}')
  if (( livre_mb < 2048 )); then
    aviso "Pouco espaço livre em disco (${livre_mb} MB). O recomendado é pelo menos 2 GB."
  else
    ok "Espaço livre em disco: ${livre_mb} MB."
  fi
}

detectar_rede() {
  titulo "Verificando a rede"

  local rota
  rota=$(ip -4 route get 1.1.1.1 2>/dev/null || true)
  IFACE=$(awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' <<<"$rota" | head -n1)
  IP_LOCAL=$(awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' <<<"$rota" | head -n1)

  if [[ -z "${IFACE:-}" || -z "${IP_LOCAL:-}" ]]; then
    erro "Não foi possível detectar a interface de rede ou o IP. Verifique a conexão com a internet."
    exit 1
  fi

  info "Interface: ${IFACE}"
  info "Endereço IP: ${IP_LOCAL}"

  if ip -4 addr show dev "$IFACE" | grep -q 'dynamic'; then
    aviso "Este servidor parece usar IP dinâmico (DHCP)."
    aviso "O Pi-hole precisa de um IP fixo. Configure via Netplan ou reserve o IP no roteador."
    perguntar "Deseja continuar mesmo assim?" N || {
      info "Configure o IP fixo (veja o README) e execute o instalador novamente."
      exit 1
    }
  else
    ok "IP aparenta ser fixo."
  fi

  if curl -fsS --max-time 15 -o /dev/null "$PIHOLE_INSTALL_URL"; then
    ok "Conexão com a internet funcionando."
  else
    erro "Sem acesso a ${PIHOLE_INSTALL_URL}. Verifique a internet e o DNS do servidor."
    exit 1
  fi
}

verificar_porta_53() {
  local ocupantes
  ocupantes=$(ss -H -lntup 'sport = :53' 2>/dev/null \
    | grep -v -E 'systemd-resolve|pihole-FTL' || true)

  if [[ -n "$ocupantes" ]]; then
    erro "A porta 53 já está em uso por outro serviço:"
    printf '%s\n' "$ocupantes" >&2
    erro "Pare esse serviço (ex.: dnsmasq, bind9, AdGuard Home) e execute novamente."
    exit 1
  fi
  ok "Porta 53 disponível."
}

verificar_pihole_existente() {
  if command -v pihole >/dev/null 2>&1; then
    aviso "O Pi-hole já está instalado neste servidor."
    info "Para atualizar, use: sudo pihole -up"
    perguntar "Deseja executar o instalador mesmo assim (reconfigurar)?" N || exit 0
  fi
}

# --------------------------------- Etapas -------------------------------------
atualizar_sistema() {
  titulo "Atualizando o servidor"
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  info "Atualizando a lista de pacotes..."
  apt-get update -y

  if (( FAZER_UPGRADE )); then
    info "Atualizando os pacotes instalados (pode demorar alguns minutos)..."
    apt-get -y \
      -o Dpkg::Options::=--force-confdef \
      -o Dpkg::Options::=--force-confold \
      upgrade
    ok "Sistema atualizado."
  else
    aviso "Atualização de pacotes ignorada (--sem-upgrade)."
  fi
}

instalar_dependencias() {
  titulo "Instalando dependências"
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a

  local pacotes=(curl ca-certificates iproute2 git)
  (( CONFIGURAR_FIREWALL )) && pacotes+=(ufw)

  apt-get install -y "${pacotes[@]}"
  ok "Dependências instaladas: ${pacotes[*]}"
}

instalar_pihole() {
  titulo "Instalando o Pi-hole"
  info "O assistente do Pi-hole vai abrir a seguir. Responda às perguntas na tela."
  info "Dica: escolha a interface ${IFACE} e mantenha o registro de consultas ativado."
  sleep 3

  TMP_INSTALADOR=$(mktemp /tmp/pihole-install.XXXXXX.sh)
  curl -fsSL "$PIHOLE_INSTALL_URL" -o "$TMP_INSTALADOR"

  # Executa a partir de um arquivo, com o terminal ligado à entrada.
  # Isso evita travamentos do formato "curl | bash" em alguns sistemas (ex.: Ubuntu 26.04).
  bash "$TMP_INSTALADOR" </dev/tty

  if ! command -v pihole >/dev/null 2>&1; then
    erro "A instalação do Pi-hole não foi concluída."
    exit 1
  fi
  ok "Pi-hole instalado."
}

definir_senha() {
  titulo "Senha do painel web"
  if perguntar "Deseja definir a senha do painel agora?" S; then
    pihole setpassword </dev/tty || aviso "Não foi possível definir a senha. Rode depois: sudo pihole setpassword"
  else
    info "Para definir depois, use: sudo pihole setpassword"
  fi
}

configurar_firewall() {
  (( CONFIGURAR_FIREWALL )) || return 0

  titulo "Firewall (UFW)"

  local rede porta_ssh
  rede=$(ip -4 route show dev "$IFACE" proto kernel scope link 2>/dev/null | awk '{print $1}' | head -n1)
  porta_ssh=$(sshd -T 2>/dev/null | awk '/^port / {print $2}' | head -n1)
  porta_ssh="${porta_ssh:-22}"

  if [[ -z "$rede" ]]; then
    aviso "Não foi possível detectar a rede local. Firewall não configurado."
    return 0
  fi

  info "Serão liberadas, somente para a rede ${rede}: SSH (${porta_ssh}), DNS (53), HTTP (80) e HTTPS (443)."
  aviso "Se você acessa este servidor por SSH de FORA da rede ${rede}, a conexão será bloqueada."

  if ! perguntar "Deseja configurar o firewall agora?" S; then
    info "Firewall ignorado. Configure depois conforme o README."
    return 0
  fi

  ufw allow from "$rede" to any port "$porta_ssh" proto tcp comment 'SSH rede local'
  ufw allow from "$rede" to any port 53 comment 'DNS Pi-hole'
  ufw allow from "$rede" to any port 80 proto tcp comment 'Painel Pi-hole HTTP'
  ufw allow from "$rede" to any port 443 proto tcp comment 'Painel Pi-hole HTTPS'
  ufw --force enable
  ok "Firewall configurado e ativado."
}

resumo_final() {
  titulo "Instalação concluída"

  ok "Pi-hole instalado e funcionando."
  printf '\n'
  printf '  %sPainel web:%s   http://%s/admin\n' "$NEGRITO" "$RESET" "$IP_LOCAL"
  printf '  %sServidor DNS:%s %s\n' "$NEGRITO" "$RESET" "$IP_LOCAL"
  printf '\n%sPróximos passos:%s\n' "$NEGRITO" "$RESET"
  printf '  1. No roteador (DHCP/LAN), defina o DNS primário como %s e deixe o secundário vazio.\n' "$IP_LOCAL"
  printf '  2. Renove a conexão nos dispositivos e teste: nslookup doubleclick.net %s\n' "$IP_LOCAL"
  printf '  3. Atualize as listas quando quiser: sudo pihole -g\n'

  if [[ -f /var/run/reboot-required ]]; then
    printf '\n'
    aviso "O sistema pede reinicialização por causa das atualizações. Reinicie assim que possível: sudo reboot"
  fi
}

# ---------------------------------- Principal ---------------------------------
main() {
  verificar_root "$@"

  printf '%s\n' "${NEGRITO}Instalador do Pi-hole para Ubuntu Server (v${VERSAO_SCRIPT})${RESET}"

  verificar_terminal
  verificar_sistema
  detectar_rede
  verificar_pihole_existente

  atualizar_sistema
  instalar_dependencias
  verificar_porta_53
  instalar_pihole
  definir_senha
  configurar_firewall
  resumo_final
}

main "$@"
