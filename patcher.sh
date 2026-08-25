#!/usr/bin/env bash

# ==============================================================================
#
#   ██████╗ ███████╗███████╗██████╗ ██████╗  █████╗ ████████╗ ██████╗██╗  ██╗
#   ██╔══██╗██╔════╝██╔════╝██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝██║  ██║
#   ██║  ██║█████╗  █████╗  ██████╔╝██████╔╝███████║   ██║   ██║     ███████║
#   ██║  ██║██╔══╝  ██╔══╝  ██╔═══╝ ██╔═══╝ ██╔══██║   ██║   ██║     ██╔══██║
#   ██████╔╝███████╗███████╗██║     ██║     ██║  ██║   ██║   ╚██████╗██║  ██║
#   ╚═════╝ ╚══════╝╚══════╝╚═╝     ╚═╝     ╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝
#
#                         DEEPPATCHER PRO v1.0.1
#
#   Installation, sécurisation, surveillance et maintenance d’un VPS personnel.
#
#   Compatibilité :
#     - Debian 11/12/13
#     - Ubuntu 22.04/24.04 et versions proches
#     - Architecture amd64 ou arm64 selon les paquets disponibles
#
#   Ne contourne aucune expiration ou restriction d’un fournisseur.
#   Ne doit pas être utilisé dans un notebook, conteneur éphémère ou serveur
#   dont tu n’as pas l’autorisation d’administration.
#
# ==============================================================================

set -Eeuo pipefail
IFS=$'\n\t'
umask 027

# ==============================================================================
# INFORMATIONS GÉNÉRALES
# ==============================================================================

readonly APP_NAME="DeepPatcher Pro"
readonly APP_VERSION="1.0.1"
readonly APP_ID="deeppatcher"
readonly APP_CONFIG_DIR="/etc/deeppatcher"
readonly APP_STATE_DIR="/var/lib/deeppatcher"
readonly APP_LOG_DIR="/var/log/deeppatcher"
readonly APP_BACKUP_DIR="/var/backups/deeppatcher"
readonly APP_BIN_DIR="/usr/local/lib/deeppatcher"
readonly APP_MAIN_LOG="${APP_LOG_DIR}/deeppatcher.log"
readonly APP_AUDIT_LOG="${APP_LOG_DIR}/audit.log"

readonly COOLIFY_INSTALL_URL="https://cdn.coollabs.io/coolify/install.sh"
readonly COOLIFY_DEFAULT_PORT="8000"

readonly STATUS_API_USER="deeppatcher-api"
readonly STATUS_API_DIR="/opt/deeppatcher/status-api"
readonly STATUS_API_ENV="/etc/deeppatcher/status-api.env"
readonly STATUS_API_PORT="9077"

readonly WATCHDOG_SCRIPT="/usr/local/sbin/deeppatcher-watchdog"
readonly BACKUP_SCRIPT="/usr/local/sbin/deeppatcher-backup"

readonly SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

DRY_RUN=0
AUTO_YES=0
QUIET=0
CURRENT_ACTION="initialisation"

# ==============================================================================
# COULEURS
# ==============================================================================

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    C_RESET="$(tput sgr0)"
    C_BOLD="$(tput bold)"
    C_DIM="$(tput dim)"
    C_RED="$(tput setaf 1)"
    C_GREEN="$(tput setaf 2)"
    C_YELLOW="$(tput setaf 3)"
    C_BLUE="$(tput setaf 4)"
    C_MAGENTA="$(tput setaf 5)"
    C_CYAN="$(tput setaf 6)"
    C_WHITE="$(tput setaf 7)"
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_BLUE=""
    C_MAGENTA=""
    C_CYAN=""
    C_WHITE=""
fi

# ==============================================================================
# AFFICHAGE
# ==============================================================================

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_raw() {
    local level="$1"
    shift
    local message="$*"

    mkdir -p "$APP_LOG_DIR" 2>/dev/null || true

    printf '[%s] [%s] %s\n' \
        "$(timestamp)" \
        "$level" \
        "$message" >>"$APP_MAIN_LOG" 2>/dev/null || true
}

audit() {
    local message="$*"

    mkdir -p "$APP_LOG_DIR" 2>/dev/null || true

    printf '[%s] user=%s action=%q message=%q\n' \
        "$(timestamp)" \
        "${SUDO_USER:-root}" \
        "$CURRENT_ACTION" \
        "$message" >>"$APP_AUDIT_LOG" 2>/dev/null || true
}

info() {
    log_raw "INFO" "$*"

    if [[ "$QUIET" -eq 0 ]]; then
        printf '%b[INFO]%b %s\n' "$C_BLUE" "$C_RESET" "$*"
    fi
}

success() {
    log_raw "SUCCESS" "$*"
    printf '%b[OK]%b %s\n' "$C_GREEN" "$C_RESET" "$*"
}

warning() {
    log_raw "WARNING" "$*"
    printf '%b[ATTENTION]%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2
}

error() {
    log_raw "ERROR" "$*"
    printf '%b[ERREUR]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2
}

fatal() {
    error "$*"
    exit 1
}

section() {
    local title="$*"

    printf '\n'
    printf '%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' \
        "$C_CYAN" "$C_RESET"
    printf '%b  %s%b\n' "$C_BOLD" "$title" "$C_RESET"
    printf '%b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' \
        "$C_CYAN" "$C_RESET"
}

pause_menu() {
    printf '\n'
    read -r -p "Appuie sur Entrée pour revenir au menu..." _
}

clear_screen() {
    if [[ -t 1 ]]; then
        clear
    fi
}

print_banner() {
    clear_screen

    printf '%b' "$C_CYAN"
    cat <<'BANNER'
    ____                  ____        __       __
   / __ \___  ___  ____  / __ \____ _/ /______/ /_  ___  _____
  / / / / _ \/ _ \/ __ \/ /_/ / __ `/ __/ ___/ __ \/ _ \/ ___/
 / /_/ /  __/  __/ /_/ / ____/ /_/ / /_/ /__/ / / /  __/ /
/_____/\___/\___/ .___/_/    \__,_/\__/\___/_/ /_/\___/_/
               /_/
BANNER
    printf '%b\n' "$C_RESET"

    printf '%b%s%b — version %s\n' \
        "$C_BOLD" \
        "$APP_NAME" \
        "$C_RESET" \
        "$APP_VERSION"

    printf '%bMaintenance et sécurisation d’un VPS autorisé%b\n' \
        "$C_DIM" \
        "$C_RESET"
}

# ==============================================================================
# GESTION DES ERREURS
# ==============================================================================

on_error() {
    local exit_code=$?
    local line_number="${BASH_LINENO[0]:-inconnue}"
    local command_name="${BASH_COMMAND:-inconnue}"

    error "Échec pendant : ${CURRENT_ACTION}"
    error "Commande : ${command_name}"
    error "Ligne : ${line_number}"
    error "Code de sortie : ${exit_code}"

    audit "failure exit_code=${exit_code} line=${line_number}"

    exit "$exit_code"
}

on_interrupt() {
    warning "Opération interrompue."
    audit "interrupted"
    exit 130
}

trap on_error ERR
trap on_interrupt INT TERM

# ==============================================================================
# UTILITAIRES
# ==============================================================================

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '%b[SIMULATION]%b ' "$C_MAGENTA" "$C_RESET"
        printf '%q ' "$@"
        printf '\n'
        return 0
    fi

    "$@"
}

retry() {
    local max_attempts="$1"
    local delay="$2"
    shift 2

    local attempt=1

    until "$@"; do
        if (( attempt >= max_attempts )); then
            return 1
        fi

        warning "Tentative ${attempt}/${max_attempts} échouée."
        sleep "$delay"
        ((attempt++))
    done
}

confirm() {
    local prompt="$1"
    local default_answer="${2:-no}"
    local answer=""

    if [[ "$AUTO_YES" -eq 1 ]]; then
        return 0
    fi

    if [[ "$default_answer" == "yes" ]]; then
        read -r -p "${prompt} [O/n] " answer
        answer="${answer:-o}"
    else
        read -r -p "${prompt} [o/N] " answer
        answer="${answer:-n}"
    fi

    case "${answer,,}" in
        o|oui|y|yes)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

write_file() {
    local destination="$1"
    local mode="$2"
    local temporary_file

    temporary_file="$(mktemp)"

    cat >"$temporary_file"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "Simulation : écriture de ${destination}"
        rm -f "$temporary_file"
        return 0
    fi

    install -D -m "$mode" "$temporary_file" "$destination"
    rm -f "$temporary_file"
}

backup_existing_file() {
    local source="$1"

    if [[ -e "$source" ]]; then
        local backup="${source}.deeppatcher.$(date '+%Y%m%d-%H%M%S').bak"
        run cp -a "$source" "$backup"
        info "Sauvegarde créée : ${backup}"
    fi
}

random_hex() {
    local bytes="${1:-32}"

    if command_exists openssl; then
        openssl rand -hex "$bytes"
    else
        head -c "$bytes" /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

sanitize_hostname() {
    local value="$1"

    printf '%s' "$value" \
        | tr '[:upper:]' '[:lower:]' \
        | sed \
            -e 's/[^a-z0-9.-]/-/g' \
            -e 's/--*/-/g' \
            -e 's/^-//' \
            -e 's/-$//'
}

valid_username() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

valid_port() {
    local port="$1"

    [[ "$port" =~ ^[0-9]+$ ]] &&
        (( port >= 1 && port <= 65535 ))
}

human_bytes() {
    local bytes="$1"

    numfmt \
        --to=iec-i \
        --suffix=B \
        "$bytes" 2>/dev/null || printf '%s octets' "$bytes"
}

# ==============================================================================
# VÉRIFICATIONS DE L’ENVIRONNEMENT
# ==============================================================================

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        fatal "Exécute ce script avec sudo : sudo ${SCRIPT_PATH}"
    fi
}

load_os_release() {
    if [[ ! -r /etc/os-release ]]; then
        fatal "Impossible d’identifier le système."
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    readonly OS_ID="${ID:-unknown}"
    readonly OS_NAME="${PRETTY_NAME:-Linux}"
    readonly OS_CODENAME="${VERSION_CODENAME:-}"
}

validate_operating_system() {
    case "$OS_ID" in
        debian|ubuntu)
            success "Système compatible : ${OS_NAME}"
            ;;
        *)
            fatal "Ce script prend uniquement en charge Debian et Ubuntu."
            ;;
    esac
}

detect_ephemeral_environment() {
    local detected=0

    if [[ -f /.dockerenv ]]; then
        warning "Un environnement Docker a été détecté."
        detected=1
    fi

    if grep -qaE \
        'docker|containerd|kubepods|lxc' \
        /proc/1/cgroup 2>/dev/null; then
        warning "Un conteneur ou environnement orchestré a été détecté."
        detected=1
    fi

    if [[ -n "${DEEPNOTE_PROJECT_ID:-}" ]] ||
       [[ -n "${COLAB_RELEASE_TAG:-}" ]] ||
       [[ -n "${KAGGLE_URL_BASE:-}" ]]; then
        warning "Un environnement notebook éphémère a été détecté."
        detected=1
    fi

    if [[ "$(ps -p 1 -o comm= 2>/dev/null || true)" != "systemd" ]]; then
        warning "systemd ne semble pas être le processus principal."
        detected=1
    fi

    if [[ "$detected" -eq 1 ]]; then
        fatal \
            "Installation refusée : utilise un VPS permanent que tu possèdes."
    fi

    success "Environnement serveur permanent détecté."
}

check_internet() {
    section "Vérification de la connexion"

    if retry 3 2 curl \
        -fsS \
        --connect-timeout 5 \
        --max-time 10 \
        https://deb.debian.org/ \
        -o /dev/null; then
        success "Connexion Internet fonctionnelle."
        return 0
    fi

    warning "La vérification Internet a échoué."
    return 1
}

check_disk_space() {
    local available_kb

    available_kb="$(df -Pk / | awk 'NR == 2 {print $4}')"

    if [[ -z "$available_kb" ]]; then
        warning "Impossible de mesurer l’espace disque."
        return
    fi

    if (( available_kb < 10 * 1024 * 1024 )); then
        warning "Moins de 10 Gio sont disponibles sur la partition racine."
    else
        success "Espace disque suffisant."
    fi
}

check_memory() {
    local memory_kb

    memory_kb="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"

    if (( memory_kb < 2 * 1024 * 1024 )); then
        warning "Moins de 2 Gio de RAM détectés. Coolify peut être lent."
    else
        success "Mémoire suffisante."
    fi
}

preflight_checks() {
    CURRENT_ACTION="vérifications préalables"

    section "Vérifications préalables"

    require_root
    load_os_release
    validate_operating_system
    detect_ephemeral_environment
    check_disk_space
    check_memory

    mkdir -p \
        "$APP_CONFIG_DIR" \
        "$APP_STATE_DIR" \
        "$APP_LOG_DIR" \
        "$APP_BACKUP_DIR" \
        "$APP_BIN_DIR"

    chmod 750 \
        "$APP_CONFIG_DIR" \
        "$APP_STATE_DIR" \
        "$APP_LOG_DIR" \
        "$APP_BACKUP_DIR" \
        "$APP_BIN_DIR"

    audit "preflight completed"
}

# ==============================================================================
# APT ET PAQUETS ESSENTIELS
# ==============================================================================

apt_update() {
    CURRENT_ACTION="actualisation des dépôts"

    section "Actualisation des dépôts"

    run env \
        DEBIAN_FRONTEND=noninteractive \
        apt-get update

    success "Dépôts actualisés."
}

install_packages() {
    CURRENT_ACTION="installation des outils essentiels"

    section "Installation des outils essentiels"

    local packages=(
        apt-transport-https
        bash-completion
        ca-certificates
        cron
        curl
        dnsutils
        fail2ban
        file
        git
        gnupg
        htop
        iproute2
        iputils-ping
        jq
        less
        lsof
        nano
        ncdu
        net-tools
        openssh-client
        openssh-server
        openssl
        python3
        python3-venv
        rsync
        shellcheck
        software-properties-common
        sudo
        tar
        tmux
        tree
        ufw
        unattended-upgrades
        unzip
        vim
        wget
        zip
    )

    apt_update

    run env \
        DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        --no-install-recommends \
        "${packages[@]}"

    if apt-cache show yt-dlp >/dev/null 2>&1; then
        run env \
            DEBIAN_FRONTEND=noninteractive \
            apt-get install -y yt-dlp
    else
        warning "yt-dlp n’est pas disponible dans les dépôts configurés."
    fi

    run systemctl enable --now ssh
    run systemctl enable --now cron

    success "Outils essentiels installés."
    audit "essential packages installed"
}

upgrade_system() {
    CURRENT_ACTION="mise à jour du système"

    section "Mise à jour du système"

    apt_update

    run env \
        DEBIAN_FRONTEND=noninteractive \
        NEEDRESTART_MODE=a \
        apt-get upgrade -y

    run env \
        DEBIAN_FRONTEND=noninteractive \
        apt-get autoremove -y

    run apt-get autoclean

    if [[ -f /var/run/reboot-required ]]; then
        warning "Un redémarrage est recommandé."
    else
        success "Aucun redémarrage obligatoire détecté."
    fi

    success "Système mis à jour."
    audit "system upgraded"
}

# ==============================================================================
# CONFIGURATION DU SERVEUR
# ==============================================================================

configure_identity() {
    CURRENT_ACTION="configuration de l’identité du serveur"

    section "Identité du serveur"

    local current_hostname
    local requested_hostname
    local timezone

    current_hostname="$(hostnamectl --static 2>/dev/null || hostname)"

    read -r -p \
        "Nom du serveur [${current_hostname}] : " \
        requested_hostname

    requested_hostname="${requested_hostname:-$current_hostname}"
    requested_hostname="$(sanitize_hostname "$requested_hostname")"

    if [[ -z "$requested_hostname" ]]; then
        fatal "Le nom du serveur est invalide."
    fi

    read -r -p \
        "Fuseau horaire [UTC] : " \
        timezone

    timezone="${timezone:-UTC}"

    if [[ ! -e "/usr/share/zoneinfo/${timezone}" ]]; then
        fatal "Fuseau horaire inconnu : ${timezone}"
    fi

    run hostnamectl set-hostname "$requested_hostname"
    run timedatectl set-timezone "$timezone"
    run timedatectl set-ntp true

    if ! grep -qE \
        "^127\.0\.1\.1[[:space:]]+${requested_hostname}([[:space:]]|$)" \
        /etc/hosts; then
        printf '127.0.1.1\t%s\n' "$requested_hostname" >>/etc/hosts
    fi

    success "Serveur configuré : ${requested_hostname}, ${timezone}."
    audit "identity configured hostname=${requested_hostname} timezone=${timezone}"
}

create_admin_user() {
    CURRENT_ACTION="création du compte administrateur"

    section "Compte administrateur"

    local username
    local ssh_key
    local home_directory
    local authorized_keys

    read -r -p "Nom du compte administrateur : " username

    if ! valid_username "$username"; then
        fatal "Nom d’utilisateur invalide."
    fi

    if id "$username" >/dev/null 2>&1; then
        info "Le compte ${username} existe déjà."
    else
        run useradd \
            --create-home \
            --shell /bin/bash \
            "$username"

        success "Compte ${username} créé."
    fi

    run usermod -aG sudo "$username"

    home_directory="$(getent passwd "$username" | cut -d: -f6)"
    authorized_keys="${home_directory}/.ssh/authorized_keys"

    printf '\n'
    info "Colle une clé publique SSH."
    info "Exemple : ssh-ed25519 AAAA... ordinateur"
    info "Laisse vide si tu veux la configurer plus tard."
    printf '\n'

    read -r -p "Clé publique SSH : " ssh_key

    if [[ -n "$ssh_key" ]]; then
        if [[ ! "$ssh_key" =~ ^ssh-(ed25519|rsa|ecdsa) ]]; then
            fatal "La clé publique ne semble pas valide."
        fi

        run install \
            -d \
            -m 700 \
            -o "$username" \
            -g "$username" \
            "${home_directory}/.ssh"

        if [[ "$DRY_RUN" -eq 0 ]]; then
            touch "$authorized_keys"
            chmod 600 "$authorized_keys"
            chown "$username:$username" "$authorized_keys"

            if ! grep -qxF "$ssh_key" "$authorized_keys"; then
                printf '%s\n' "$ssh_key" >>"$authorized_keys"
            fi
        fi

        success "Clé SSH installée pour ${username}."
    else
        warning "Aucune clé SSH installée."
        warning "Ne désactive pas les mots de passe avant d’avoir testé une clé."
    fi

    success "Compte ${username} ajouté au groupe sudo."
    audit "admin user configured username=${username}"
}

configure_swap() {
    CURRENT_ACTION="configuration de la mémoire swap"

    section "Mémoire swap"

    local swap_size_gb

    if swapon --show --noheadings | grep -q .; then
        info "Une zone swap est déjà active :"
        swapon --show
        return 0
    fi

    read -r -p "Taille de la swap en Gio [2] : " swap_size_gb
    swap_size_gb="${swap_size_gb:-2}"

    if [[ ! "$swap_size_gb" =~ ^[0-9]+$ ]] ||
       (( swap_size_gb < 1 || swap_size_gb > 64 )); then
        fatal "Choisis une taille comprise entre 1 et 64 Gio."
    fi

    if command_exists fallocate; then
        run fallocate -l "${swap_size_gb}G" /swapfile
    else
        run dd \
            if=/dev/zero \
            of=/swapfile \
            bs=1M \
            count="$((swap_size_gb * 1024))" \
            status=progress
    fi

    run chmod 600 /swapfile
    run mkswap /swapfile
    run swapon /swapfile

    if ! grep -qE '^/swapfile[[:space:]]' /etc/fstab; then
        printf '/swapfile none swap sw 0 0\n' >>/etc/fstab
    fi

    write_file /etc/sysctl.d/99-deeppatcher-memory.conf 0644 <<'SYSCTL'
# Géré par DeepPatcher Pro.
vm.swappiness=10
vm.vfs_cache_pressure=50
SYSCTL

    run sysctl --system >/dev/null

    success "Swap de ${swap_size_gb} Gio activée."
    audit "swap configured size_gb=${swap_size_gb}"
}

# ==============================================================================
# PARE-FEU
# ==============================================================================

detect_ssh_port() {
    local detected_port

    detected_port="$(
        sshd -T 2>/dev/null |
            awk '$1 == "port" {print $2; exit}'
    )"

    printf '%s' "${detected_port:-22}"
}

configure_firewall() {
    CURRENT_ACTION="configuration du pare-feu"

    section "Pare-feu UFW"

    local ssh_port

    ssh_port="$(detect_ssh_port)"

    if ! valid_port "$ssh_port"; then
        ssh_port="22"
    fi

    info "Port SSH détecté : ${ssh_port}"

    run ufw default deny incoming
    run ufw default allow outgoing

    run ufw allow "${ssh_port}/tcp" comment "SSH"
    run ufw allow "80/tcp" comment "HTTP"
    run ufw allow "443/tcp" comment "HTTPS"
    run ufw allow "${COOLIFY_DEFAULT_PORT}/tcp" comment "Coolify initial"

    run ufw logging low
    run ufw --force enable

    printf '\n'
    ufw status verbose || true

    success "Pare-feu activé."
    warning \
        "Le port ${COOLIFY_DEFAULT_PORT} pourra être fermé après la configuration HTTPS."
    audit "firewall configured ssh_port=${ssh_port}"
}

# ==============================================================================
# FAIL2BAN
# ==============================================================================

configure_fail2ban() {
    CURRENT_ACTION="configuration de Fail2ban"

    section "Protection anti-bruteforce"

    write_file /etc/fail2ban/jail.d/deeppatcher.local 0644 <<'FAIL2BAN'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = ssh
filter  = sshd
logpath = %(sshd_log)s
maxretry = 5
FAIL2BAN

    run systemctl enable fail2ban
    run systemctl restart fail2ban

    sleep 2

    if systemctl is-active --quiet fail2ban; then
        success "Fail2ban est actif."
    else
        fatal "Fail2ban n’a pas démarré."
    fi

    fail2ban-client status sshd 2>/dev/null || true
    audit "fail2ban configured"
}

# ==============================================================================
# DURCISSEMENT SSH
# ==============================================================================

harden_ssh() {
    CURRENT_ACTION="durcissement SSH"

    section "Durcissement SSH"

    local username
    local home_directory
    local authorized_keys
    local config_file="/etc/ssh/sshd_config.d/99-deeppatcher-hardening.conf"

    warning "Cette action désactive l’authentification SSH par mot de passe."
    warning "Teste d’abord ta clé SSH dans une deuxième session."

    read -r -p "Compte possédant une clé SSH valide : " username

    if ! id "$username" >/dev/null 2>&1; then
        fatal "Le compte ${username} n’existe pas."
    fi

    home_directory="$(getent passwd "$username" | cut -d: -f6)"
    authorized_keys="${home_directory}/.ssh/authorized_keys"

    if [[ ! -s "$authorized_keys" ]]; then
        fatal "Aucune clé SSH trouvée pour ${username}."
    fi

    if ! confirm \
        "As-tu testé cette clé dans une autre session SSH ?" \
        "no"; then
        warning "Durcissement annulé."
        return 0
    fi

    backup_existing_file "$config_file"

    write_file "$config_file" 0644 <<'SSHCONFIG'
# Géré par DeepPatcher Pro.
# Vérifier avec : sshd -t

PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no

PermitRootLogin prohibit-password
PermitEmptyPasswords no

X11Forwarding no
PrintMotd no

MaxAuthTries 4
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

AllowAgentForwarding yes
AllowTcpForwarding yes

UsePAM yes
SSHCONFIG

    if ! sshd -t; then
        rm -f "$config_file"
        fatal "Configuration SSH invalide. Modification annulée."
    fi

    run systemctl reload ssh

    success "SSH durci avec authentification par clé."
    warning "Garde la session actuelle ouverte pendant ton test."
    audit "ssh hardened key_user=${username}"
}

# ==============================================================================
# MISES À JOUR AUTOMATIQUES
# ==============================================================================

configure_automatic_updates() {
    CURRENT_ACTION="configuration des mises à jour automatiques"

    section "Mises à jour de sécurité automatiques"

    run env \
        DEBIAN_FRONTEND=noninteractive \
        apt-get install -y unattended-upgrades

    write_file \
        /etc/apt/apt.conf.d/20auto-upgrades \
        0644 <<'APTCONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
APTCONF

    write_file \
        /etc/apt/apt.conf.d/52deeppatcher-unattended-upgrades \
        0644 <<'APTCONF'
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
APTCONF

    run systemctl enable --now apt-daily.timer
    run systemctl enable --now apt-daily-upgrade.timer

    success "Mises à jour automatiques activées."
    audit "automatic updates configured"
}

# ==============================================================================
# DOCKER
# ==============================================================================

remove_conflicting_docker_packages() {
    local conflicting_packages=(
        docker.io
        docker-doc
        docker-compose
        podman-docker
        containerd
        runc
    )

    local installed=()
    local package_name

    for package_name in "${conflicting_packages[@]}"; do
        if dpkg-query \
            -W \
            -f='${Status}' \
            "$package_name" 2>/dev/null |
            grep -q "install ok installed"; then
            installed+=("$package_name")
        fi
    done

    if (( ${#installed[@]} > 0 )); then
        warning \
            "Suppression des paquets Docker incompatibles : ${installed[*]}"

        run env \
            DEBIAN_FRONTEND=noninteractive \
            apt-get remove -y \
            "${installed[@]}"
    fi
}

install_docker() {
    CURRENT_ACTION="installation de Docker"

    section "Installation de Docker Engine"

    if command_exists docker &&
       docker info >/dev/null 2>&1; then
        success "Docker est déjà installé et fonctionnel."
        docker --version
        return 0
    fi

    remove_conflicting_docker_packages

    run install \
        -m 0755 \
        -d \
        /etc/apt/keyrings

    run curl \
        -fsSL \
        "https://download.docker.com/linux/${OS_ID}/gpg" \
        -o /etc/apt/keyrings/docker.asc

    run chmod a+r /etc/apt/keyrings/docker.asc

    if [[ -z "$OS_CODENAME" ]]; then
        fatal "Impossible de déterminer le nom de version du système."
    fi

    cat >/etc/apt/sources.list.d/docker.list <<DOCKER_REPOSITORY
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${OS_ID} ${OS_CODENAME} stable
DOCKER_REPOSITORY

    apt_update

    run env \
        DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    write_file /etc/docker/daemon.json 0644 <<'DOCKERCONFIG'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "5"
  },
  "live-restore": true
}
DOCKERCONFIG

    run systemctl daemon-reload
    run systemctl enable docker
    run systemctl restart docker

    if ! docker info >/dev/null 2>&1; then
        fatal "Docker a été installé, mais le service ne répond pas."
    fi

    success "Docker installé."
    docker --version
    docker compose version

    audit "docker installed"
}

# ==============================================================================
# COOLIFY
# ==============================================================================

public_ip() {
    local ip=""

    ip="$(
        curl \
            -4fsS \
            --connect-timeout 3 \
            --max-time 5 \
            https://api.ipify.org 2>/dev/null ||
        true
    )"

    if [[ -z "$ip" ]]; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi

    printf '%s' "${ip:-indisponible}"
}

check_coolify_ports() {
    local port

    for port in 80 443 "$COOLIFY_DEFAULT_PORT"; do
        if ss -ltnH |
            awk '{print $4}' |
            grep -qE "(^|:|\])${port}$"; then
            warning "Le port ${port} est déjà utilisé."
        fi
    done
}

install_coolify() {
    CURRENT_ACTION="installation de Coolify"

    section "Installation de Coolify"

    if [[ -d /data/coolify ]]; then
        warning "Le dossier /data/coolify existe déjà."
        warning "Coolify semble déjà installé ou partiellement installé."

        if docker ps \
            --format '{{.Names}}' 2>/dev/null |
            grep -qi coolify; then
            success "Des conteneurs Coolify sont actifs."
            show_coolify_url
            return 0
        fi
    fi

    if ! command_exists docker; then
        install_docker
    fi

    if ! docker info >/dev/null 2>&1; then
        fatal "Docker doit fonctionner avant l’installation de Coolify."
    fi

    check_memory
    check_disk_space
    check_coolify_ports

    printf '\n'
    warning "L’installateur sera téléchargé depuis le site officiel de Coolify."
    warning "Vérifie toujours l’adresse officielle avant exécution."
    printf '\n'

    if ! confirm "Installer Coolify maintenant ?" "no"; then
        warning "Installation annulée."
        return 0
    fi

    local installer
    installer="$(mktemp /tmp/coolify-installer.XXXXXX.sh)"

    run curl \
        -fsSL \
        --proto '=https' \
        --tlsv1.2 \
        "$COOLIFY_INSTALL_URL" \
        -o "$installer"

    if [[ "$DRY_RUN" -eq 0 ]]; then
        if [[ ! -s "$installer" ]]; then
            rm -f "$installer"
            fatal "L’installateur téléchargé est vide."
        fi

        chmod 700 "$installer"

        info "Empreinte SHA-256 de l’installateur :"
        sha256sum "$installer"

        bash "$installer"
        rm -f "$installer"
    fi

    success "Installation de Coolify terminée."
    show_coolify_url

    audit "coolify installation executed"
}

show_coolify_url() {
    local ip
    ip="$(public_ip)"

    printf '\n'
    printf '%bURL initiale :%b http://%s:%s\n' \
        "$C_BOLD" \
        "$C_RESET" \
        "$ip" \
        "$COOLIFY_DEFAULT_PORT"

    printf '\n'
    warning "Crée immédiatement le premier compte administrateur."
    warning "Configure ensuite un domaine HTTPS."
    warning "Ferme le port 8000 une fois l’accès HTTPS validé."
}

close_coolify_setup_port() {
    CURRENT_ACTION="fermeture du port initial Coolify"

    section "Fermeture du port Coolify initial"

    warning \
        "Ne fais cela qu’après avoir vérifié ton domaine HTTPS Coolify."

    if ! confirm \
        "Fermer le port ${COOLIFY_DEFAULT_PORT}/tcp ?" \
        "no"; then
        return 0
    fi

    run ufw delete allow \
        "${COOLIFY_DEFAULT_PORT}/tcp"

    success "Port ${COOLIFY_DEFAULT_PORT}/tcp fermé."
    audit "coolify setup port closed"
}

# ==============================================================================
# WATCHDOG DOCKER
# ==============================================================================

install_watchdog() {
    CURRENT_ACTION="installation du watchdog"

    section "Watchdog Docker"

    write_file "$WATCHDOG_SCRIPT" 0750 <<'WATCHDOG'
#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly LOG_FILE="/var/log/deeppatcher/watchdog.log"
readonly LOCK_FILE="/run/lock/deeppatcher-watchdog.lock"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"

exec 9>"$LOCK_FILE"

if ! flock -n 9; then
    exit 0
fi

log() {
    printf '[%s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$*" >>"$LOG_FILE"
}

log "Début de la vérification."

if ! systemctl is-active --quiet docker; then
    log "Docker est inactif. Tentative de redémarrage."

    if systemctl restart docker; then
        log "Docker redémarré."
        sleep 10
    else
        log "Échec du redémarrage de Docker."
        exit 1
    fi
fi

if ! docker info >/dev/null 2>&1; then
    log "L’API Docker ne répond pas."
    exit 1
fi

mapfile -t unhealthy_containers < <(
    docker ps \
        --filter health=unhealthy \
        --format '{{.ID}}'
)

if (( ${#unhealthy_containers[@]} > 0 )); then
    for container_id in "${unhealthy_containers[@]}"; do
        container_name="$(
            docker inspect \
                --format '{{.Name}}' \
                "$container_id" |
            sed 's#^/##'
        )"

        log "Conteneur unhealthy détecté : ${container_name}."

        if docker restart "$container_id" >/dev/null; then
            log "Conteneur redémarré : ${container_name}."
        else
            log "Échec du redémarrage : ${container_name}."
        fi
    done
else
    log "Aucun conteneur unhealthy."
fi

docker system df >>"$LOG_FILE" 2>&1 || true

log "Fin de la vérification."
WATCHDOG

    write_file \
        /etc/systemd/system/deeppatcher-watchdog.service \
        0644 <<'SERVICE'
[Unit]
Description=DeepPatcher Docker watchdog
Documentation=man:systemd.service(5)
Wants=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/deeppatcher-watchdog

User=root
Group=root

Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7

NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

ReadWritePaths=/var/log/deeppatcher /run/lock
SERVICE

    write_file \
        /etc/systemd/system/deeppatcher-watchdog.timer \
        0644 <<'TIMER'
[Unit]
Description=Exécute DeepPatcher Watchdog toutes les cinq minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
RandomizedDelaySec=30s
Persistent=true
AccuracySec=15s

[Install]
WantedBy=timers.target
TIMER

    run systemctl daemon-reload
    run systemctl enable --now deeppatcher-watchdog.timer

    success "Watchdog installé et activé."
    info "Fréquence : toutes les cinq minutes."
    info "Journal : /var/log/deeppatcher/watchdog.log"

    audit "watchdog installed"
}

# ==============================================================================
# SAUVEGARDES LOCALES
# ==============================================================================

install_backup_system() {
    CURRENT_ACTION="installation du système de sauvegarde"

    section "Sauvegardes automatiques"

    write_file "$BACKUP_SCRIPT" 0750 <<'BACKUP'
#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly BACKUP_ROOT="/var/backups/deeppatcher"
readonly LOG_FILE="/var/log/deeppatcher/backup.log"
readonly RETENTION_DAYS=7
readonly LOCK_FILE="/run/lock/deeppatcher-backup.lock"

mkdir -p "$BACKUP_ROOT"
mkdir -p "$(dirname "$LOG_FILE")"

exec 9>"$LOCK_FILE"

if ! flock -n 9; then
    exit 0
fi

log() {
    printf '[%s] %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$*" >>"$LOG_FILE"
}

timestamp="$(date '+%Y%m%d-%H%M%S')"
hostname_value="$(hostname -s)"
archive="${BACKUP_ROOT}/${hostname_value}-${timestamp}.tar.gz"
temporary_archive="${archive}.partial"

items=()

[[ -d /data/coolify ]] &&
    items+=("data/coolify")

[[ -d /etc/deeppatcher ]] &&
    items+=("etc/deeppatcher")

[[ -d /etc/docker ]] &&
    items+=("etc/docker")

[[ -d /etc/ssh/sshd_config.d ]] &&
    items+=("etc/ssh/sshd_config.d")

[[ -d /etc/fail2ban ]] &&
    items+=("etc/fail2ban")

if (( ${#items[@]} == 0 )); then
    log "Aucun élément à sauvegarder."
    exit 0
fi

log "Création de ${archive}."

if tar \
    --one-file-system \
    --xattrs \
    --acls \
    --numeric-owner \
    --ignore-failed-read \
    -C / \
    -czf "$temporary_archive" \
    "${items[@]}" >>"$LOG_FILE" 2>&1; then

    mv "$temporary_archive" "$archive"
    chmod 600 "$archive"

    sha256sum "$archive" >"${archive}.sha256"
    chmod 600 "${archive}.sha256"

    log "Sauvegarde terminée : ${archive}."
else
    rm -f "$temporary_archive"
    log "Échec de la sauvegarde."
    exit 1
fi

find "$BACKUP_ROOT" \
    -type f \
    -mtime "+${RETENTION_DAYS}" \
    \( -name '*.tar.gz' -o -name '*.sha256' \) \
    -delete

log "Rotation terminée."
BACKUP

    write_file \
        /etc/systemd/system/deeppatcher-backup.service \
        0644 <<'SERVICE'
[Unit]
Description=Sauvegarde locale DeepPatcher
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/deeppatcher-backup

User=root
Group=root

Nice=15
IOSchedulingClass=idle

NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

ReadWritePaths=/var/backups/deeppatcher
ReadWritePaths=/var/log/deeppatcher
ReadWritePaths=/run/lock
SERVICE

    write_file \
        /etc/systemd/system/deeppatcher-backup.timer \
        0644 <<'TIMER'
[Unit]
Description=Sauvegarde DeepPatcher quotidienne

[Timer]
OnCalendar=*-*-* 03:30:00
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
TIMER

    run systemctl daemon-reload
    run systemctl enable --now deeppatcher-backup.timer

    success "Sauvegardes quotidiennes activées."
    info "Dossier : ${APP_BACKUP_DIR}"
    info "Rétention locale : 7 jours"
    warning "Une sauvegarde locale ne remplace pas une sauvegarde externe."

    audit "backup system installed"
}

run_backup_now() {
    CURRENT_ACTION="sauvegarde manuelle"

    section "Sauvegarde manuelle"

    if [[ ! -x "$BACKUP_SCRIPT" ]]; then
        install_backup_system
    fi

    run systemctl start deeppatcher-backup.service

    success "Sauvegarde exécutée."

    find "$APP_BACKUP_DIR" \
        -maxdepth 1 \
        -type f \
        -name '*.tar.gz' \
        -printf '%TY-%Tm-%Td %TH:%TM  %10s  %f\n' |
        sort -r |
        head -n 10

    audit "manual backup executed"
}

# ==============================================================================
# API LOCALE DE STATUT
# ==============================================================================

install_status_api() {
    CURRENT_ACTION="installation de l’API de statut"

    section "API locale de statut"

    if ! command_exists node; then
        info "Installation de Node.js depuis les dépôts du système."

        run env \
            DEBIAN_FRONTEND=noninteractive \
            apt-get install -y nodejs
    fi

    local token
    token="$(random_hex 32)"

    if ! id "$STATUS_API_USER" >/dev/null 2>&1; then
        run useradd \
            --system \
            --no-create-home \
            --home-dir "$STATUS_API_DIR" \
            --shell /usr/sbin/nologin \
            "$STATUS_API_USER"
    fi

    run install \
        -d \
        -m 0750 \
        -o root \
        -g "$STATUS_API_USER" \
        "$STATUS_API_DIR"

    write_file "${STATUS_API_DIR}/server.js" 0640 <<'JAVASCRIPT'
'use strict';

const http = require('http');
const os = require('os');
const fs = require('fs');
const crypto = require('crypto');

const HOST = process.env.STATUS_API_HOST || '127.0.0.1';
const PORT = Number(process.env.STATUS_API_PORT || 9077);
const TOKEN = process.env.STATUS_API_TOKEN || '';
const STARTED_AT = new Date();

const MAX_REQUESTS_PER_MINUTE = 60;
const requestCounters = new Map();

function sendJson(response, statusCode, payload) {
    const body = JSON.stringify(payload, null, 2);

    response.writeHead(statusCode, {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Length': Buffer.byteLength(body),
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
        'Referrer-Policy': 'no-referrer',
        'Content-Security-Policy': "default-src 'none'"
    });

    response.end(body);
}

function secureEquals(firstValue, secondValue) {
    const firstBuffer = Buffer.from(String(firstValue));
    const secondBuffer = Buffer.from(String(secondValue));

    if (firstBuffer.length !== secondBuffer.length) {
        return false;
    }

    return crypto.timingSafeEqual(firstBuffer, secondBuffer);
}

function isAuthorized(request) {
    const authorization = request.headers.authorization || '';
    const expected = `Bearer ${TOKEN}`;

    return TOKEN.length >= 32 && secureEquals(authorization, expected);
}

function isRateLimited(request) {
    const address = request.socket.remoteAddress || 'unknown';
    const currentMinute = Math.floor(Date.now() / 60000);
    const key = `${address}:${currentMinute}`;
    const count = (requestCounters.get(key) || 0) + 1;

    requestCounters.set(key, count);

    if (requestCounters.size > 1000) {
        for (const storedKey of requestCounters.keys()) {
            if (!storedKey.endsWith(`:${currentMinute}`)) {
                requestCounters.delete(storedKey);
            }
        }
    }

    return count > MAX_REQUESTS_PER_MINUTE;
}

function networkAddresses() {
    const interfaces = os.networkInterfaces();
    const addresses = [];

    for (const [name, records] of Object.entries(interfaces)) {
        for (const record of records || []) {
            if (!record.internal) {
                addresses.push({
                    interface: name,
                    family: record.family,
                    address: record.address
                });
            }
        }
    }

    return addresses;
}

function diskInformation() {
    try {
        const statistics = fs.statfsSync('/');
        const total = statistics.blocks * statistics.bsize;
        const available = statistics.bavail * statistics.bsize;

        return {
            filesystem: '/',
            totalBytes: total,
            availableBytes: available,
            usedBytes: total - available,
            usedPercent:
                total > 0
                    ? Number((((total - available) / total) * 100).toFixed(2))
                    : null
        };
    } catch (error) {
        return {
            filesystem: '/',
            error: 'disk_information_unavailable'
        };
    }
}

function statusPayload() {
    const totalMemory = os.totalmem();
    const freeMemory = os.freemem();

    return {
        service: 'deeppatcher-status-api',
        version: '1.0.1',
        timestamp: new Date().toISOString(),
        apiStartedAt: STARTED_AT.toISOString(),
        system: {
            hostname: os.hostname(),
            platform: os.platform(),
            release: os.release(),
            architecture: os.arch(),
            uptimeSeconds: Math.floor(os.uptime()),
            loadAverage: os.loadavg(),
            processors: os.cpus().length
        },
        memory: {
            totalBytes: totalMemory,
            freeBytes: freeMemory,
            usedBytes: totalMemory - freeMemory,
            usedPercent: Number(
                (((totalMemory - freeMemory) / totalMemory) * 100).toFixed(2)
            )
        },
        disk: diskInformation(),
        network: networkAddresses()
    };
}

const server = http.createServer((request, response) => {
    if (isRateLimited(request)) {
        return sendJson(response, 429, {
            error: 'rate_limit_exceeded'
        });
    }

    if (request.method !== 'GET') {
        return sendJson(response, 405, {
            error: 'method_not_allowed'
        });
    }

    const requestUrl = new URL(
        request.url,
        `http://${request.headers.host || 'localhost'}`
    );

    if (requestUrl.pathname === '/health') {
        return sendJson(response, 200, {
            status: 'ok',
            timestamp: new Date().toISOString()
        });
    }

    if (requestUrl.pathname === '/v1/status') {
        if (!isAuthorized(request)) {
            return sendJson(response, 401, {
                error: 'unauthorized'
            });
        }

        return sendJson(response, 200, statusPayload());
    }

    return sendJson(response, 404, {
        error: 'not_found'
    });
});

server.requestTimeout = 10000;
server.headersTimeout = 5000;
server.keepAliveTimeout = 5000;
server.maxRequestsPerSocket = 100;

server.on('clientError', (_error, socket) => {
    if (socket.writable) {
        socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
    }
});

server.listen(PORT, HOST, () => {
    console.log(
        JSON.stringify({
            event: 'server_started',
            host: HOST,
            port: PORT,
            timestamp: new Date().toISOString()
        })
    );
});

function shutdown(signal) {
    console.log(
        JSON.stringify({
            event: 'shutdown',
            signal,
            timestamp: new Date().toISOString()
        })
    );

    server.close(() => process.exit(0));

    setTimeout(() => process.exit(1), 5000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

process.on('uncaughtException', error => {
    console.error(error);
    process.exit(1);
});

process.on('unhandledRejection', error => {
    console.error(error);
    process.exit(1);
});
JAVASCRIPT

    if [[ "$DRY_RUN" -eq 0 ]]; then
        chown \
            root:"$STATUS_API_USER" \
            "${STATUS_API_DIR}/server.js"
    fi

    write_file "$STATUS_API_ENV" 0640 <<STATUSENV
STATUS_API_HOST=127.0.0.1
STATUS_API_PORT=${STATUS_API_PORT}
STATUS_API_TOKEN=${token}
STATUSENV

    if [[ "$DRY_RUN" -eq 0 ]]; then
        chown root:"$STATUS_API_USER" "$STATUS_API_ENV"
    fi

    write_file \
        /etc/systemd/system/deeppatcher-status-api.service \
        0644 <<SERVICE
[Unit]
Description=DeepPatcher read-only status API
After=network.target

[Service]
Type=simple

User=${STATUS_API_USER}
Group=${STATUS_API_USER}

EnvironmentFile=${STATUS_API_ENV}
ExecStart=/usr/bin/node ${STATUS_API_DIR}/server.js

Restart=on-failure
RestartSec=5s
TimeoutStopSec=10s

NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
ProtectProc=invisible
ProcSubset=pid

RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
RestrictRealtime=true
LockPersonality=true
MemoryDenyWriteExecute=true

CapabilityBoundingSet=
AmbientCapabilities=

[Install]
WantedBy=multi-user.target
SERVICE

    run systemctl daemon-reload
    run systemctl enable --now deeppatcher-status-api.service

    if [[ "$DRY_RUN" -eq 0 ]]; then
        sleep 2

        if ! systemctl is-active --quiet deeppatcher-status-api; then
            journalctl \
                -u deeppatcher-status-api \
                --no-pager \
                -n 50 || true

            fatal "L’API de statut n’a pas démarré."
        fi
    fi

    success "API locale installée."
    info "Healthcheck : http://127.0.0.1:${STATUS_API_PORT}/health"
    info "Statut : http://127.0.0.1:${STATUS_API_PORT}/v1/status"
    printf '%bToken :%b %s\n' "$C_BOLD" "$C_RESET" "$token"

    printf '\n'
    info "Exemple :"
    printf 'curl -H %q %q\n' \
        "Authorization: Bearer ${token}" \
        "http://127.0.0.1:${STATUS_API_PORT}/v1/status"

    printf '\n'
    warning "L’API écoute uniquement sur 127.0.0.1."
    warning "Elle n’exécute aucune commande et ne fournit aucun terminal web."
    warning "Ne publie pas directement cette API sur Internet."

    audit "status API installed localhost_port=${STATUS_API_PORT}"
}

# ==============================================================================
# INFORMATIONS ET DIAGNOSTIC
# ==============================================================================

show_system_information() {
    CURRENT_ACTION="affichage des informations système"

    section "Informations système"

    local ip
    local ssh_port
    local docker_version="non installé"
    local coolify_state="non détecté"

    ip="$(public_ip)"
    ssh_port="$(detect_ssh_port)"

    if command_exists docker; then
        docker_version="$(docker --version 2>/dev/null || true)"
    fi

    if [[ -d /data/coolify ]]; then
        coolify_state="dossier présent"
    fi

    printf '%-24s %s\n' "Nom du serveur :" "$(hostname)"
    printf '%-24s %s\n' "Système :" "$OS_NAME"
    printf '%-24s %s\n' "Noyau :" "$(uname -r)"
    printf '%-24s %s\n' "Architecture :" "$(uname -m)"
    printf '%-24s %s\n' "IP publique :" "$ip"
    printf '%-24s %s\n' "Port SSH :" "$ssh_port"
    printf '%-24s %s\n' "Uptime :" "$(uptime -p)"
    printf '%-24s %s\n' "Docker :" "$docker_version"
    printf '%-24s %s\n' "Coolify :" "$coolify_state"

    if [[ "$ip" != "indisponible" ]]; then
        printf '%-24s http://%s:%s\n' \
            "URL Coolify initiale :" \
            "$ip" \
            "$COOLIFY_DEFAULT_PORT"
    fi

    printf '\n%bMémoire%b\n' "$C_BOLD" "$C_RESET"
    free -h

    printf '\n%bDisque%b\n' "$C_BOLD" "$C_RESET"
    df -hT /

    printf '\n%bCharge%b\n' "$C_BOLD" "$C_RESET"
    uptime

    printf '\n%bPare-feu%b\n' "$C_BOLD" "$C_RESET"
    ufw status verbose 2>/dev/null || true

    printf '\n%bServices%b\n' "$C_BOLD" "$C_RESET"

    local services=(
        ssh
        docker
        fail2ban
        deeppatcher-watchdog.timer
        deeppatcher-backup.timer
        deeppatcher-status-api
    )

    local service_name
    local service_state

    for service_name in "${services[@]}"; do
        service_state="$(
            systemctl is-active "$service_name" 2>/dev/null ||
            true
        )"

        printf '%-36s %s\n' \
            "$service_name" \
            "${service_state:-absent}"
    done
}

run_diagnostics() {
    CURRENT_ACTION="diagnostic du serveur"

    section "Diagnostic complet"

    local problems=0

    diagnostic_test() {
        local label="$1"
        shift

        printf '%-45s' "$label"

        if "$@" >/dev/null 2>&1; then
            printf '%bOK%b\n' "$C_GREEN" "$C_RESET"
        else
            printf '%bÉCHEC%b\n' "$C_RED" "$C_RESET"
            ((problems++)) || true
        fi
    }

    diagnostic_test \
        "Résolution DNS" \
        getent hosts deb.debian.org

    diagnostic_test \
        "Connexion HTTPS" \
        curl -fsS --max-time 10 https://deb.debian.org/ -o /dev/null

    diagnostic_test \
        "Service SSH" \
        systemctl is-active --quiet ssh

    diagnostic_test \
        "Configuration SSH valide" \
        sshd -t

    diagnostic_test \
        "Pare-feu actif" \
        systemctl is-active --quiet ufw

    diagnostic_test \
        "Fail2ban actif" \
        systemctl is-active --quiet fail2ban

    if command_exists docker; then
        diagnostic_test \
            "Service Docker" \
            systemctl is-active --quiet docker

        diagnostic_test \
            "API Docker" \
            docker info
    else
        warning "Docker n’est pas installé."
    fi

    if systemctl cat deeppatcher-status-api.service \
        >/dev/null 2>&1; then
        diagnostic_test \
            "API de statut" \
            curl \
                -fsS \
                --max-time 5 \
                "http://127.0.0.1:${STATUS_API_PORT}/health"
    fi

    printf '\n'

    if (( problems == 0 )); then
        success "Tous les tests exécutés sont réussis."
    else
        warning "${problems} test(s) ont échoué."
    fi

    audit "diagnostics completed problems=${problems}"
}

show_logs() {
    CURRENT_ACTION="consultation des journaux"

    section "Journaux"

    printf '%s\n' \
        "[1] Journal principal DeepPatcher" \
        "[2] Watchdog" \
        "[3] Sauvegardes" \
        "[4] Docker" \
        "[5] Coolify" \
        "[6] Fail2ban" \
        "[7] SSH" \
        "[8] API de statut" \
        "[0] Retour"

    printf '\n'

    local log_choice
    read -r -p "Choix : " log_choice

    case "$log_choice" in
        1)
            tail -n 200 "$APP_MAIN_LOG" 2>/dev/null ||
                warning "Journal indisponible."
            ;;
        2)
            tail -n 200 \
                /var/log/deeppatcher/watchdog.log 2>/dev/null ||
                warning "Journal indisponible."
            ;;
        3)
            tail -n 200 \
                /var/log/deeppatcher/backup.log 2>/dev/null ||
                warning "Journal indisponible."
            ;;
        4)
            journalctl \
                -u docker \
                --no-pager \
                -n 200
            ;;
        5)
            if command_exists docker; then
                docker ps -a \
                    --format \
                    'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

                printf '\n'

                docker ps \
                    --format '{{.Names}}' |
                    grep -i coolify |
                    while read -r container_name; do
                        printf '\n=== %s ===\n' "$container_name"
                        docker logs \
                            --tail 50 \
                            "$container_name" 2>&1 || true
                    done
            fi
            ;;
        6)
            journalctl \
                -u fail2ban \
                --no-pager \
                -n 200
            ;;
        7)
            journalctl \
                -u ssh \
                --no-pager \
                -n 200
            ;;
        8)
            journalctl \
                -u deeppatcher-status-api \
                --no-pager \
                -n 200
            ;;
        0)
            return 0
            ;;
        *)
            warning "Choix invalide."
            ;;
    esac
}

# ==============================================================================
# NETTOYAGE DOCKER
# ==============================================================================

docker_cleanup() {
    CURRENT_ACTION="nettoyage Docker"

    section "Nettoyage Docker"

    if ! command_exists docker; then
        fatal "Docker n’est pas installé."
    fi

    printf '\n'
    docker system df
    printf '\n'

    warning "Les images et caches inutilisés seront supprimés."
    warning "Les volumes ne seront pas supprimés."

    if ! confirm "Continuer le nettoyage Docker ?" "no"; then
        return 0
    fi

    run docker container prune -f
    run docker image prune -a -f
    run docker builder prune -a -f
    run docker network prune -f

    printf '\n'
    docker system df

    success "Nettoyage Docker terminé."
    audit "docker cleanup executed"
}

# ==============================================================================
# INSTALLATION COMPLÈTE
# ==============================================================================

full_installation() {
    CURRENT_ACTION="installation complète"

    section "Installation complète"

    warning "Cette installation modifiera le système."
    warning "SSH ne sera pas durci automatiquement sans vérification de clé."

    if ! confirm "Lancer l’installation complète ?" "no"; then
        warning "Installation annulée."
        return 0
    fi

    install_packages
    upgrade_system
    configure_identity
    configure_swap
    configure_firewall
    configure_fail2ban
    configure_automatic_updates
    install_docker
    install_watchdog
    install_backup_system
    install_status_api
    install_coolify

    section "Installation terminée"

    success "La base du serveur est prête."

    printf '\n'
    printf '%s\n' \
        "Étapes recommandées :" \
        "  1. Créer et tester un compte SSH avec clé." \
        "  2. Activer le durcissement SSH depuis le menu." \
        "  3. Créer le premier compte Coolify." \
        "  4. Pointer un domaine DNS vers l’IP du VPS." \
        "  5. Configurer HTTPS dans Coolify." \
        "  6. Fermer ensuite le port 8000." \
        "  7. Copier les sauvegardes vers un stockage externe."

    show_coolify_url

    audit "full installation completed"
}

# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================

print_menu() {
    print_banner

    printf '\n'
    printf '%bInstallation%b\n' "$C_BOLD" "$C_RESET"
    printf '  %b[1]%b  Installer les outils essentiels\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[2]%b  Mettre le système à jour\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[3]%b  Configurer le serveur\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[4]%b  Créer un compte administrateur\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[5]%b  Configurer la swap\n' \
        "$C_CYAN" "$C_RESET"

    printf '\n'
    printf '%bSécurité%b\n' "$C_BOLD" "$C_RESET"
    printf '  %b[6]%b  Configurer le pare-feu\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[7]%b  Configurer Fail2ban\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[8]%b  Durcir SSH\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[9]%b  Activer les mises à jour automatiques\n' \
        "$C_CYAN" "$C_RESET"

    printf '\n'
    printf '%bDocker et Coolify%b\n' "$C_BOLD" "$C_RESET"
    printf '  %b[10]%b Installer Docker\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[11]%b Installer Coolify\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[12]%b Fermer le port initial Coolify\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[13]%b Nettoyer Docker\n' \
        "$C_CYAN" "$C_RESET"

    printf '\n'
    printf '%bSupervision%b\n' "$C_BOLD" "$C_RESET"
    printf '  %b[14]%b Installer le watchdog\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[15]%b Installer les sauvegardes\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[16]%b Exécuter une sauvegarde\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[17]%b Installer l’API locale de statut\n' \
        "$C_CYAN" "$C_RESET"

    printf '\n'
    printf '%bDiagnostic%b\n' "$C_BOLD" "$C_RESET"
    printf '  %b[18]%b Afficher les informations système\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[19]%b Lancer le diagnostic complet\n' \
        "$C_CYAN" "$C_RESET"
    printf '  %b[20]%b Afficher les journaux\n' \
        "$C_CYAN" "$C_RESET"

    printf '\n'
    printf '%bAutomatisation%b\n' "$C_BOLD" "$C_RESET"
    printf '  %b[99]%b Installation complète\n' \
        "$C_GREEN" "$C_RESET"

    printf '\n'
    printf '  %b[0]%b  Quitter\n' "$C_RED" "$C_RESET"
    printf '\n'
}

main_menu() {
    while true; do
        print_menu

        local choice
        read -r -p "DeepPatcher > " choice

        case "$choice" in
            1)
                install_packages
                pause_menu
                ;;
            2)
                upgrade_system
                pause_menu
                ;;
            3)
                configure_identity
                pause_menu
                ;;
            4)
                create_admin_user
                pause_menu
                ;;
            5)
                configure_swap
                pause_menu
                ;;
            6)
                configure_firewall
                pause_menu
                ;;
            7)
                configure_fail2ban
                pause_menu
                ;;
            8)
                harden_ssh
                pause_menu
                ;;
            9)
                configure_automatic_updates
                pause_menu
                ;;
            10)
                install_docker
                pause_menu
                ;;
            11)
                install_coolify
                pause_menu
                ;;
            12)
                close_coolify_setup_port
                pause_menu
                ;;
            13)
                docker_cleanup
                pause_menu
                ;;
            14)
                install_watchdog
                pause_menu
                ;;
            15)
                install_backup_system
                pause_menu
                ;;
            16)
                run_backup_now
                pause_menu
                ;;
            17)
                install_status_api
                pause_menu
                ;;
            18)
                show_system_information
                pause_menu
                ;;
            19)
                run_diagnostics
                pause_menu
                ;;
            20)
                show_logs
                pause_menu
                ;;
            99)
                full_installation
                pause_menu
                ;;
            0|q|quit|exit)
                success "Fermeture de DeepPatcher."
                exit 0
                ;;
            *)
                warning "Choix invalide."
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# ARGUMENTS
# ==============================================================================

show_help() {
    cat <<HELP
${APP_NAME} ${APP_VERSION}

Utilisation :
  sudo ${SCRIPT_PATH} [options]

Options :
  --help            Affiche cette aide
  --version         Affiche la version
  --yes             Répond automatiquement oui aux confirmations
  --dry-run         Simule certaines opérations
  --quiet           Réduit les messages
  --full-install    Lance l’installation complète
  --diagnostics     Lance uniquement les diagnostics
  --info            Affiche les informations système
  --backup          Lance une sauvegarde
  --install-docker  Installe Docker
  --install-coolify Installe Coolify

Exemples :
  sudo ${SCRIPT_PATH}
  sudo ${SCRIPT_PATH} --diagnostics
  sudo ${SCRIPT_PATH} --install-docker
  sudo ${SCRIPT_PATH} --full-install
HELP
}

parse_arguments() {
    local requested_action="menu"

    while (( $# > 0 )); do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                printf '%s %s\n' "$APP_NAME" "$APP_VERSION"
                exit 0
                ;;
            --yes|-y)
                AUTO_YES=1
                ;;
            --dry-run)
                DRY_RUN=1
                ;;
            --quiet|-q)
                QUIET=1
                ;;
            --full-install)
                requested_action="full-install"
                ;;
            --diagnostics)
                requested_action="diagnostics"
                ;;
            --info)
                requested_action="info"
                ;;
            --backup)
                requested_action="backup"
                ;;
            --install-docker)
                requested_action="install-docker"
                ;;
            --install-coolify)
                requested_action="install-coolify"
                ;;
            *)
                fatal "Argument inconnu : $1"
                ;;
        esac

        shift
    done

    printf '%s' "$requested_action"
}

# ==============================================================================
# POINT D’ENTRÉE
# ==============================================================================

main() {
    require_root
    load_os_release

    local requested_action
    requested_action="$(parse_arguments "$@")"

    preflight_checks

    case "$requested_action" in
        menu)
            main_menu
            ;;
        full-install)
            full_installation
            ;;
        diagnostics)
            run_diagnostics
            ;;
        info)
            show_system_information
            ;;
        backup)
            run_backup_now
            ;;
        install-docker)
            install_docker
            ;;
        install-coolify)
            install_coolify
            ;;
        *)
            fatal "Action interne inconnue : ${requested_action}"
            ;;
    esac
}

main "$@"
