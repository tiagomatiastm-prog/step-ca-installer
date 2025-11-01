# step-ca-installer

Installation automatisée d'une autorité de certification (CA) avec step-ca sur Debian 13.

## Description

Ce projet permet d'installer et configurer automatiquement **step-ca**, une autorité de certification moderne et simple d'utilisation, développée par Smallstep. Step-ca permet de gérer des certificats TLS/SSL pour sécuriser vos services, applications et infrastructures.

## Fonctionnalités

- Installation automatique de step-ca sur Debian 13
- Configuration d'une CA racine et d'une CA intermédiaire
- Génération automatique de certificats et clés sécurisées
- Support ACME (Automated Certificate Management Environment)
- API REST pour la gestion des certificats
- Interface CLI step pour l'administration
- Service systemd pour la gestion de step-ca

## Prérequis

- Système d'exploitation : **Debian 13** (bookworm ou supérieur)
- Accès root ou utilisateur avec privilèges sudo
- Connexion Internet pour télécharger les paquets
- Nom de domaine ou FQDN configuré (recommandé)

## Installation rapide

### Méthode 1 : Installation en une ligne (recommandée)

```bash
curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/step-ca-installer/main/install-step-ca.sh | sudo bash
```

### Méthode 2 : Installation manuelle

```bash
# Télécharger le script
wget https://raw.githubusercontent.com/tiagomatiastm-prog/step-ca-installer/main/install-step-ca.sh

# Rendre le script exécutable
chmod +x install-step-ca.sh

# Exécuter le script
sudo ./install-step-ca.sh
```

### Méthode 3 : Installation avec configuration personnalisée

Vous pouvez personnaliser l'installation en définissant des variables d'environnement :

```bash
# Installation avec nom de domaine personnalisé
CA_DNS_NAME=ca.exemple.com curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/step-ca-installer/main/install-step-ca.sh | sudo bash

# Installation avec nom de domaine et email personnalisés
CA_DNS_NAME=ca.exemple.com ADMIN_EMAIL=admin@exemple.com curl -fsSL https://raw.githubusercontent.com/tiagomatiastm-prog/step-ca-installer/main/install-step-ca.sh | sudo bash
```

**Variables d'environnement disponibles** :
- `CA_DNS_NAME` : Nom de domaine de la CA (défaut: `ca.local`)
- `ADMIN_EMAIL` : Email de l'administrateur (défaut: `admin@${CA_DNS_NAME}`)

## Déploiement avec Ansible

Pour déployer step-ca sur plusieurs serveurs avec Ansible, consultez le guide [DEPLOYMENT.md](DEPLOYMENT.md).

## Configuration

Le script d'installation configure automatiquement :
- CA avec un nom de domaine par défaut (personnalisable)
- Certificats root et intermediate
- ACME provisioner pour Let's Encrypt-like workflow
- JWK provisioner pour l'authentification par token
- API REST sur le port 9000 (par défaut)

## Utilisation

### Démarrer/Arrêter le service

```bash
sudo systemctl start step-ca
sudo systemctl stop step-ca
sudo systemctl status step-ca
```

### Obtenir un certificat avec step CLI

```bash
# Obtenir un certificat pour un serveur
step ca certificate mon-serveur.exemple.com server.crt server.key

# Lister les certificats actifs
step ca provisioner list
```

### Obtenir un certificat avec ACME

```bash
# Utiliser avec certbot
certbot certonly --standalone \
  --server https://votre-ca.exemple.com:9000/acme/acme/directory \
  -d mon-domaine.exemple.com
```

## Informations de connexion

Après l'installation, les informations de connexion et la configuration sont stockées dans :
- `/root/step-ca-info.txt` - Informations de connexion et mots de passe
- `/etc/step-ca/` - Répertoire de configuration de step-ca
- `/var/log/step-ca/` - Logs de step-ca

## Sécurité

- Les mots de passe et secrets sont générés automatiquement avec une complexité élevée
- Les clés privées sont protégées avec des permissions restrictives (600)
- Le service tourne avec un utilisateur dédié non-privilégié
- TLS activé par défaut pour toutes les communications

## Technologies utilisées

- **step-ca** : Autorité de certification moderne
- **step CLI** : Client en ligne de commande
- **systemd** : Gestion du service
- **Bash** : Script d'installation
- **Ansible** : Déploiement automatisé (optionnel)

## Structure du projet

```
step-ca-installer/
├── install-step-ca.sh      # Script d'installation principal
├── deploy-step-ca.yml      # Playbook Ansible
├── inventory.ini           # Inventaire Ansible
├── templates/              # Templates Ansible
│   ├── step-ca.service.j2
│   └── step-ca-info.txt.j2
├── DEPLOYMENT.md           # Guide de déploiement Ansible
└── README.md               # Ce fichier
```

## Dépannage

### Le service ne démarre pas

```bash
# Vérifier les logs
sudo journalctl -u step-ca -f

# Vérifier la configuration
step-ca validate /etc/step-ca/config/ca.json
```

### Problèmes de certificats

```bash
# Renouveler le certificat du serveur CA
step ca renew /etc/step-ca/certs/intermediate_ca.crt /etc/step-ca/secrets/intermediate_ca_key

# Vérifier l'état de la CA
step ca health
```

## Contribution

Les contributions sont les bienvenues ! N'hésitez pas à ouvrir une issue ou une pull request.

## Licence

MIT License

## Auteur

Tiago Matias

## Liens utiles

- [Documentation officielle step-ca](https://smallstep.com/docs/step-ca)
- [GitHub Smallstep](https://github.com/smallstep/certificates)
- [Guide ACME](https://smallstep.com/docs/step-ca/acme-basics)
