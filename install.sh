#!/bin/bash

# =====================================================
#   Debian Server Installer Wizard
#   Clean • Modern • Tech Style
# =====================================================

CONFIG_FILE="./config.conf"

# -------------------- SZÍNEK -------------------------
RESET="\e[0m"
BOLD="\e[1m"

BLUE="\e[38;5;39m"
CYAN="\e[38;5;51m"
GREEN="\e[38;5;82m"
YELLOW="\e[38;5;220m"
RED="\e[38;5;196m"
GRAY="\e[38;5;245m"

ICON_OK="${GREEN}✔${RESET}"
ICON_FAIL="${RED}✖${RESET}"
ICON_RUN="${CYAN}➜${RESET}"
ICON_INFO="${BLUE}ℹ${RESET}"

# ------------------ ALAP ELLENŐRZÉSEK -----------------

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}[ERROR] Hiányzik a config.conf fájl!${RESET}"
    exit 1
fi

source "$CONFIG_FILE"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Root jogosultság szükséges!${RESET}"
    exit 1
fi

# -------------------- LOGOLÁS -------------------------

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# -------------------- UI ELEMEK -----------------------

banner() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "╔══════════════════════════════════════════╗"
    echo "║        Debian Server Installer            ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${RESET}"
}

section() {
    echo
    echo -e "${BLUE}${BOLD}▶ $1${RESET}"
    echo -e "${GRAY}──────────────────────────────────────────${RESET}"
}

run_cmd() {
    local DESC="$1"
    local CMD="$2"

    echo -ne "  ${ICON_RUN} ${DESC} ... "

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET}"
        return
    fi

    eval "$CMD" &>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${ICON_OK}"
    else
        echo -e "${ICON_FAIL}"
    fi
}

check_port() {
    local PORT="$1"
    local NAME="$2"

    if nc -z localhost "$PORT" &>/dev/null; then
        echo -e "  ${ICON_OK} ${NAME} (${PORT}) aktív"
    else
        echo -e "  ${ICON_FAIL} ${NAME} (${PORT}) nem elérhető"
    fi
}

# ---------------- INTERNET CHECK ---------------------

banner
section "Rendszer ellenőrzés"

echo -ne "  ${ICON_RUN} Internet kapcsolat (8.8.8.8) ... "
if ping -c 2 -W 2 8.8.8.8 &>/dev/null; then
    echo -e "${ICON_OK}"
else
    echo -e "${ICON_FAIL}"
    echo -e "${RED}Nincs internet, a telepítés megszakad!${RESET}"
    exit 1
fi

echo -e "  ${ICON_INFO} Log fájl: ${GRAY}${LOG_FILE}${RESET}"
echo -e "  ${ICON_INFO} Dry-run: ${GRAY}${DRY_RUN}${RESET}"

# ---------------- TELEPÍTÉS ---------------------------

section "Rendszer frissítés"
run_cmd "APT update" "apt update -y"

section "Alap csomagok"

[[ "$INSTALL_APACHE" == "true" ]]   && run_cmd "Apache2" "apt install -y apache2"
[[ "$INSTALL_PHP" == "true" ]]      && run_cmd "PHP + Apache modul" "apt install -y php libapache2-mod-php"
[[ "$INSTALL_SSH" == "true" ]]      && run_cmd "OpenSSH Server" "apt install -y openssh-server"
[[ "$INSTALL_MOSQUITTO" == "true" ]]&& run_cmd "Mosquitto MQTT" "apt install -y mosquitto mosquitto-clients"
[[ "$INSTALL_MARIADB" == "true" ]]  && run_cmd "MariaDB" "apt install -y mariadb-server"

run_cmd "Curl" "apt install -y curl"

# ---------------- NODE-RED ----------------------------

if [[ "$INSTALL_NODE_RED" == "true" ]]; then
    section "Node-RED"

    [[ -z "$NODE_VERSION" ]] && {
        echo -e "${RED}[ERROR] NODE_VERSION nincs megadva!${RESET}"
        exit 1
    }

    run_cmd "NodeSource repo" "curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -"
    run_cmd "Node.js" "apt install -y nodejs"
    run_cmd "Node-RED" "npm install -g --unsafe-perm node-red"

    run_cmd "Systemd reload" "systemctl daemon-reexec && systemctl daemon-reload"
fi

# ---------------- APACHE SSL --------------------------

if [[ "$INSTALL_APACHE" == "true" && "$ENABLE_APACHE_SSL" == "true" ]]; then
    section "Apache SSL"
    run_cmd "SSL modul" "a2enmod ssl"
    run_cmd "default-ssl site" "a2ensite default-ssl"
    run_cmd "Apache reload" "systemctl reload apache2"
fi

# ---------------- UFW --------------------------------

if [[ "$INSTALL_UFW" == "true" ]]; then
    section "Tűzfal (UFW)"

    run_cmd "UFW install" "apt install -y ufw"
    run_cmd "SSH port" "ufw allow ${PORT_SSH}/tcp"
    run_cmd "HTTP port" "ufw allow ${PORT_HTTP}/tcp"
    run_cmd "HTTPS port" "ufw allow ${PORT_HTTPS}/tcp"
    run_cmd "MQTT port" "ufw allow ${PORT_MQTT}/tcp"
    run_cmd "Node-RED port" "ufw allow ${PORT_NODE_RED}/tcp"

    [[ "$ALLOW_MARIADB_EXTERNAL" == "true" ]] && \
        run_cmd "MariaDB port" "ufw allow ${PORT_MARIADB}/tcp"

    run_cmd "UFW enable" "ufw --force enable && ufw reload"
fi

# ---------------- SERVICES ----------------------------

section "Szolgáltatások indítása"

run_cmd "Enable + restart services" \
"systemctl enable apache2 ssh mosquitto mariadb &&
 systemctl restart apache2 ssh mosquitto mariadb"

# ---------------- PORT CHECK --------------------------

section "Port ellenőrzés"

[[ "$INSTALL_SSH" == "true" ]]       && check_port "$PORT_SSH" "SSH"
[[ "$INSTALL_APACHE" == "true" ]]    && check_port "$PORT_HTTP" "HTTP"
[[ "$INSTALL_APACHE" == "true" ]]    && check_port "$PORT_HTTPS" "HTTPS"
[[ "$INSTALL_MOSQUITTO" == "true" ]] && check_port "$PORT_MQTT" "MQTT"
[[ "$INSTALL_NODE_RED" == "true" ]]  && check_port "$PORT_NODE_RED" "Node-RED"
[[ "$INSTALL_MARIADB" == "true" ]]   && check_port "$PORT_MARIADB" "MariaDB"

# ---------------- FINISH ------------------------------

echo
echo -e "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║        ✔ Telepítés befejezve!             ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${RESET}"
