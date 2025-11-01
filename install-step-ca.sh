#!/bin/bash

################################################################################
# Script d'installation de step-ca (Autorité de Certification)
# Système supporté : Debian 13
# Auteur : Tiago Matias
# Description : Installation automatique de step-ca avec configuration de base
################################################################################

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonction pour afficher les messages
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Fonction d'aide
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Installation automatisée de step-ca (Autorité de Certification) sur Debian 13

OPTIONS:
    --ca-dns <nom>          Nom de domaine de la CA (ex: ca.exemple.com)
    --email <email>         Email de l'administrateur
    --reverse-proxy         Activer le mode reverse proxy (bind sur 127.0.0.1)
    --bind-address <addr>   Adresse d'écoute (défaut: 0.0.0.0 ou 127.0.0.1 si reverse-proxy)
    --port <port>           Port de la CA (défaut: 9000)
    -h, --help              Afficher ce message d'aide

EXEMPLES:
    # Installation simple
    sudo $0

    # Installation avec configuration personnalisée
    sudo $0 --ca-dns ca.exemple.com --email admin@exemple.com

    # Installation derrière un reverse proxy
    sudo $0 --ca-dns ca.exemple.com --email admin@exemple.com --reverse-proxy

    # Installation via curl avec arguments
    curl -fsSL <url> | sudo bash -s -- --ca-dns ca.exemple.com --email admin@exemple.com --reverse-proxy

VARIABLES D'ENVIRONNEMENT (alternative):
    CA_DNS_NAME             Nom de domaine de la CA
    ADMIN_EMAIL             Email de l'administrateur
    BEHIND_REVERSE_PROXY    true/false pour activer le mode reverse proxy
    BIND_ADDRESS            Adresse d'écoute
    CA_PORT                 Port de la CA

EOF
    exit 0
}

# Parser les arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ca-dns)
                CA_DNS_NAME="$2"
                shift 2
                ;;
            --email)
                ADMIN_EMAIL="$2"
                shift 2
                ;;
            --reverse-proxy)
                BEHIND_REVERSE_PROXY="true"
                shift
                ;;
            --bind-address)
                BIND_ADDRESS="$2"
                shift 2
                ;;
            --port)
                CA_PORT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                print_error "Option inconnue: $1"
                echo "Utilisez --help pour voir les options disponibles"
                exit 1
                ;;
        esac
    done
}

# Parser les arguments avant tout
parse_args "$@"

# Vérifier que le script est exécuté en tant que root
if [[ $EUID -ne 0 ]]; then
   print_error "Ce script doit être exécuté en tant que root (sudo)"
   exit 1
fi

# Vérifier que c'est bien Debian
if ! grep -q "Debian" /etc/os-release; then
    print_error "Ce script est conçu pour Debian 13. Système actuel non supporté."
    exit 1
fi

print_message "====================================================="
print_message "  Installation de step-ca (Autorité de Certification)"
print_message "====================================================="

# Déterminer l'utilisateur réel (celui qui a lancé sudo)
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_USER="root"
    REAL_HOME="/root"
fi

print_message "Utilisateur détecté : $REAL_USER"

# Variables de configuration
STEP_VERSION="0.28.7"  # Version de step CLI
STEP_CA_VERSION="0.28.4"  # Version de step-ca
STEP_USER="step"
STEP_GROUP="step"
STEP_HOME="/etc/step-ca"
STEP_AUTH_DIR="${STEP_HOME}/authorities/default"
STEP_CONFIG_DIR="${STEP_AUTH_DIR}/config"
STEP_SECRETS_DIR="${STEP_AUTH_DIR}/secrets"
STEP_CERTS_DIR="${STEP_AUTH_DIR}/certs"
STEP_DB_DIR="${STEP_AUTH_DIR}/db"

# Générer un mot de passe sécurisé pour la CA
CA_PASSWORD=$(openssl rand -base64 32)
PROVISIONER_PASSWORD=$(openssl rand -base64 32)

# Configuration via arguments CLI (priorité), variables d'environnement, ou valeurs par défaut
# Les arguments CLI ont déjà été parsés et ont défini les variables si fournis
# Sinon on utilise les variables d'environnement ou les valeurs par défaut

# Port de la CA (arguments CLI > env > défaut)
CA_PORT="${CA_PORT:-${CA_PORT_ENV:-9000}}"

# Nom de domaine CA (arguments CLI > env > défaut)
CA_DNS_NAME="${CA_DNS_NAME:-ca.local}"

# Email admin (arguments CLI > env > défaut basé sur CA_DNS_NAME)
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${CA_DNS_NAME}}"

# Configuration reverse proxy (arguments CLI > env > défaut)
BEHIND_REVERSE_PROXY="${BEHIND_REVERSE_PROXY:-false}"

# Adresse d'écoute (arguments CLI > env > défaut basé sur reverse proxy)
if [ "$BEHIND_REVERSE_PROXY" = "true" ]; then
    BIND_ADDRESS="${BIND_ADDRESS:-127.0.0.1}"
else
    BIND_ADDRESS="${BIND_ADDRESS:-0.0.0.0}"
fi

print_message "Configuration :"
print_message "  - Nom de domaine CA : $CA_DNS_NAME"
print_message "  - Email admin : $ADMIN_EMAIL"
print_message "  - Port API : $CA_PORT"
print_message "  - Adresse d'écoute : $BIND_ADDRESS:$CA_PORT"
if [ "$BEHIND_REVERSE_PROXY" = "true" ]; then
    print_message "  - Mode reverse proxy : ACTIVÉ"
fi

# Mise à jour du système
print_message "Mise à jour du système..."
apt-get update -qq

# Installation des dépendances
print_message "Installation des dépendances..."
apt-get install -y -qq wget curl jq

# Téléchargement et installation de step CLI
print_message "Téléchargement de step CLI v${STEP_VERSION}..."
STEP_CLI_DEB="step-cli_${STEP_VERSION}-1_amd64.deb"
wget -q "https://github.com/smallstep/cli/releases/download/v${STEP_VERSION}/${STEP_CLI_DEB}" -O "/tmp/${STEP_CLI_DEB}"

if [ ! -s "/tmp/${STEP_CLI_DEB}" ]; then
    print_error "Échec du téléchargement de step CLI"
    exit 1
fi

print_message "Installation de step CLI..."
dpkg -i "/tmp/${STEP_CLI_DEB}"
rm -f "/tmp/${STEP_CLI_DEB}"

# Téléchargement et installation de step-ca
print_message "Téléchargement de step-ca v${STEP_CA_VERSION}..."
STEP_CA_DEB="step-ca_${STEP_CA_VERSION}-1_amd64.deb"
wget -q "https://github.com/smallstep/certificates/releases/download/v${STEP_CA_VERSION}/${STEP_CA_DEB}" -O "/tmp/${STEP_CA_DEB}"

if [ ! -s "/tmp/${STEP_CA_DEB}" ]; then
    print_error "Échec du téléchargement de step-ca"
    exit 1
fi

print_message "Installation de step-ca..."
dpkg -i "/tmp/${STEP_CA_DEB}"
rm -f "/tmp/${STEP_CA_DEB}"

# Vérifier les installations
print_message "Vérification des installations..."
step version
step-ca version

# Créer l'utilisateur step si nécessaire
if ! id "$STEP_USER" &>/dev/null; then
    print_message "Création de l'utilisateur $STEP_USER..."
    useradd --system --home "$STEP_HOME" --shell /bin/false "$STEP_USER"
fi

# Créer le répertoire de base (step ca init créera le reste)
print_message "Création du répertoire de base..."
mkdir -p "$STEP_HOME"
chown $STEP_USER:$STEP_GROUP "$STEP_HOME"

# Initialiser la CA
print_message "Initialisation de l'autorité de certification..."
export STEPPATH="$STEP_HOME"

# Créer le fichier de mot de passe temporaire
echo "$CA_PASSWORD" > /tmp/ca_password.txt

# Initialiser la CA avec step ca init
step ca init \
    --name="Step CA" \
    --dns="$CA_DNS_NAME" \
    --address="${BIND_ADDRESS}:${CA_PORT}" \
    --provisioner="admin@${CA_DNS_NAME}" \
    --password-file=/tmp/ca_password.txt \
    --provisioner-password-file=/tmp/ca_password.txt \
    --deployment-type=standalone \
    --context=default

# Nettoyer le fichier temporaire de mot de passe
rm -f /tmp/ca_password.txt

# Configurer les permissions
print_message "Configuration des permissions..."
chown -R ${STEP_USER}:${STEP_GROUP} "$STEP_HOME"
chmod 700 "$STEP_SECRETS_DIR"
find "$STEP_SECRETS_DIR" -type f -exec chmod 600 {} \;

# Créer le service systemd
print_message "Création du service systemd..."
cat > /etc/systemd/system/step-ca.service <<EOF
[Unit]
Description=step-ca Certificate Authority
After=network-online.target
Wants=network-online.target
Documentation=https://smallstep.com/docs/step-ca

[Service]
Type=simple
User=${STEP_USER}
Group=${STEP_GROUP}
Environment="STEPPATH=${STEP_HOME}"
ExecStart=/usr/bin/step-ca ${STEP_CONFIG_DIR}/ca.json --password-file=${STEP_SECRETS_DIR}/password.txt
Restart=on-failure
RestartSec=10

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${STEP_HOME}
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF

# Créer le fichier de mot de passe pour le service
echo "$CA_PASSWORD" > "${STEP_SECRETS_DIR}/password.txt"
chown ${STEP_USER}:${STEP_GROUP} "${STEP_SECRETS_DIR}/password.txt"
chmod 600 "${STEP_SECRETS_DIR}/password.txt"

# Activer et démarrer le service
print_message "Activation et démarrage du service step-ca..."
systemctl daemon-reload
systemctl enable step-ca
systemctl start step-ca

# Attendre que le service démarre
sleep 3

# Vérifier l'état du service
if systemctl is-active --quiet step-ca; then
    print_message "Service step-ca démarré avec succès"
else
    print_error "Le service step-ca n'a pas pu démarrer"
    journalctl -u step-ca -n 20 --no-pager
    exit 1
fi

# Tester la connexion à la CA
print_message "Test de la connexion à la CA..."
if step ca health &>/dev/null; then
    print_message "CA accessible et fonctionnelle"
else
    print_warning "La CA ne répond pas immédiatement (peut nécessiter quelques secondes)"
fi

# Créer le fichier d'informations
INFO_FILE="${REAL_HOME}/step-ca-info.txt"
print_message "Création du fichier d'informations : $INFO_FILE"

cat > "$INFO_FILE" <<EOF
========================================
  Informations step-ca
========================================

Installation terminée le : $(date)

INFORMATIONS DE CONNEXION
-------------------------
URL de la CA       : https://${CA_DNS_NAME}:${CA_PORT}
Email admin        : ${ADMIN_EMAIL}
Mot de passe CA    : ${CA_PASSWORD}

API ENDPOINTS
-------------
Health Check       : https://${CA_DNS_NAME}:${CA_PORT}/health
ACME Directory     : https://${CA_DNS_NAME}:${CA_PORT}/acme/acme/directory
Provisioners       : https://${CA_DNS_NAME}:${CA_PORT}/provisioners

FICHIERS DE CONFIGURATION
-------------------------
Config Directory   : ${STEP_CONFIG_DIR}
CA Config          : ${STEP_CONFIG_DIR}/ca.json
Secrets Directory  : ${STEP_SECRETS_DIR}
Certificates Dir   : ${STEP_CERTS_DIR}
Database Directory : ${STEP_DB_DIR}

Root Certificate   : ${STEP_CERTS_DIR}/root_ca.crt
Intermediate Cert  : ${STEP_CERTS_DIR}/intermediate_ca.crt

COMMANDES UTILES
----------------
# Vérifier l'état de la CA
step ca health

# Lister les provisioners
step ca provisioner list

# Obtenir un certificat
step ca certificate <nom-domaine> <cert.crt> <cert.key>

# Renouveler un certificat
step ca renew <cert.crt> <cert.key>

# Révoquer un certificat
step ca revoke <serial-number>

# Bootstrap step CLI (première utilisation)
step ca bootstrap --ca-url https://${CA_DNS_NAME}:${CA_PORT} --fingerprint \$(step certificate fingerprint ${STEP_CERTS_DIR}/root_ca.crt)

GESTION DU SERVICE
------------------
Démarrer    : sudo systemctl start step-ca
Arrêter     : sudo systemctl stop step-ca
Redémarrer  : sudo systemctl restart step-ca
Statut      : sudo systemctl status step-ca
Logs        : sudo journalctl -u step-ca -f

SÉCURITÉ
--------
- Le mot de passe de la CA est stocké dans : ${STEP_SECRETS_DIR}/password.txt
- Conservez ce fichier en lieu sûr
- Permissions restrictives appliquées sur les clés privées (600)
- Service s'exécute avec l'utilisateur dédié : ${STEP_USER}

DOCUMENTATION
-------------
Site officiel      : https://smallstep.com/docs/step-ca
GitHub             : https://github.com/smallstep/certificates
Documentation ACME : https://smallstep.com/docs/step-ca/acme-basics

========================================
EOF

chown ${REAL_USER}:${REAL_USER} "$INFO_FILE" 2>/dev/null || chown ${REAL_USER} "$INFO_FILE"
chmod 600 "$INFO_FILE"

print_message "====================================================="
print_message "  Installation de step-ca terminée avec succès !"
print_message "====================================================="
print_message ""
print_message "Informations importantes :"
print_message "  - URL CA         : https://${CA_DNS_NAME}:${CA_PORT}"
print_message "  - Email admin    : ${ADMIN_EMAIL}"
print_message "  - Mot de passe   : (voir ${INFO_FILE})"
print_message ""
print_message "Fichier d'informations créé : $INFO_FILE"
print_message ""
print_message "Pour tester la CA :"
print_message "  step ca health"
print_message ""
print_message "Pour obtenir un certificat :"
print_message "  step ca certificate mon-serveur.exemple.com server.crt server.key"
print_message ""
print_message "Logs du service :"
print_message "  sudo journalctl -u step-ca -f"
print_message ""
print_message "====================================================="
