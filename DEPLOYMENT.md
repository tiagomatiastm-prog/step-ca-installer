# Guide de déploiement Ansible - step-ca

Ce guide explique comment déployer step-ca sur un ou plusieurs serveurs en utilisant Ansible.

## Prérequis

### Sur la machine de contrôle (où vous exécutez Ansible)

- Ansible installé (version 2.9 ou supérieure)
- Accès SSH aux serveurs cibles
- Clés SSH configurées pour l'authentification

### Sur les serveurs cibles

- Debian 13 (bookworm ou supérieur)
- Utilisateur avec privilèges sudo
- Connexion Internet pour télécharger les paquets

## Installation d'Ansible

Si Ansible n'est pas déjà installé sur votre machine de contrôle :

```bash
# Sur Debian/Ubuntu
sudo apt update
sudo apt install ansible

# Vérifier l'installation
ansible --version
```

## Configuration de l'inventaire

Éditez le fichier `inventory.ini` pour ajouter vos serveurs :

```ini
[step_ca_servers]
ca-prod ansible_host=192.168.1.100 ansible_user=debian
ca-backup ansible_host=192.168.1.101 ansible_user=debian
```

### Options de configuration

Vous pouvez personnaliser les variables dans `inventory.ini` :

```ini
[step_ca_servers]
ca-prod ansible_host=192.168.1.100 ansible_user=debian

[step_ca_servers:vars]
ca_dns_name=ca.exemple.com
admin_email=admin@exemple.com
ca_port=9000
```

## Configuration SSH

Assurez-vous que vous pouvez vous connecter aux serveurs sans mot de passe :

```bash
# Tester la connexion SSH
ssh debian@192.168.1.100

# Si nécessaire, copier votre clé SSH
ssh-copy-id debian@192.168.1.100
```

## Déploiement

### 1. Vérifier la connectivité

Testez la connexion à vos serveurs :

```bash
ansible -i inventory.ini step_ca_servers -m ping
```

Sortie attendue :
```
ca-prod | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

### 2. Lancer le déploiement

Déployez step-ca sur tous les serveurs de l'inventaire :

```bash
ansible-playbook -i inventory.ini deploy-step-ca.yml
```

Avec sudo (si nécessaire) :

```bash
ansible-playbook -i inventory.ini deploy-step-ca.yml --ask-become-pass
```

### 3. Déploiement sur un serveur spécifique

Pour déployer sur un seul serveur :

```bash
ansible-playbook -i inventory.ini deploy-step-ca.yml --limit ca-prod
```

## Variables personnalisables

Vous pouvez surcharger les variables par défaut de plusieurs façons :

### Variables disponibles

| Variable | Description | Défaut |
|----------|-------------|--------|
| `ca_dns_name` | Nom de domaine de la CA | `ca.local` |
| `admin_email` | Email de l'administrateur | `admin@{{ ca_dns_name }}` |
| `ca_port` | Port d'écoute de la CA | `9000` |
| `behind_reverse_proxy` | Mode reverse proxy (true/false) | `false` |
| `bind_address` | Adresse d'écoute | `0.0.0.0` ou `127.0.0.1` si reverse proxy |
| `step_version` | Version de step CLI | `0.28.7` |
| `step_ca_version` | Version de step-ca | `0.28.4` |

### Dans l'inventaire

```ini
[step_ca_servers:vars]
ca_dns_name=ca.exemple.com
admin_email=admin@exemple.com
ca_port=9000
behind_reverse_proxy=false
step_version=0.28.7
step_ca_version=0.28.4
```

**Exemple avec reverse proxy** :
```ini
[step_ca_servers:vars]
ca_dns_name=ca.exemple.com
admin_email=admin@exemple.com
behind_reverse_proxy=true
bind_address=127.0.0.1
```

### En ligne de commande

```bash
# Configuration de base
ansible-playbook -i inventory.ini deploy-step-ca.yml \
  -e "ca_dns_name=ca.exemple.com" \
  -e "admin_email=admin@exemple.com"

# Avec reverse proxy
ansible-playbook -i inventory.ini deploy-step-ca.yml \
  -e "ca_dns_name=ca.exemple.com" \
  -e "admin_email=admin@exemple.com" \
  -e "behind_reverse_proxy=true" \
  -e "bind_address=127.0.0.1"
```

### Dans un fichier de variables

Créez un fichier `vars.yml` :

```yaml
ca_dns_name: ca.exemple.com
admin_email: admin@exemple.com
ca_port: 9000
behind_reverse_proxy: false
bind_address: 0.0.0.0
step_version: 0.28.7
step_ca_version: 0.28.4
```

**Exemple avec reverse proxy** (`vars-reverse-proxy.yml`) :
```yaml
ca_dns_name: ca.exemple.com
admin_email: admin@exemple.com
ca_port: 9000
behind_reverse_proxy: true
bind_address: 127.0.0.1
step_version: 0.28.7
step_ca_version: 0.28.4
```

Utilisez-le lors du déploiement :

```bash
ansible-playbook -i inventory.ini deploy-step-ca.yml -e "@vars.yml"
```

## Vérification post-déploiement

### Vérifier l'état du service

```bash
ansible -i inventory.ini step_ca_servers -m shell -a "systemctl status step-ca" --become
```

### Vérifier la santé de la CA

```bash
ansible -i inventory.ini step_ca_servers -m shell -a "step ca health" --become
```

### Récupérer les informations de connexion

Les informations de connexion sont stockées dans `~/step-ca-info.txt` sur chaque serveur :

```bash
ansible -i inventory.ini step_ca_servers -m fetch \
  -a "src=~/step-ca-info.txt dest=./credentials/ flat=no"
```

## Gestion du service après déploiement

### Redémarrer le service

```bash
ansible -i inventory.ini step_ca_servers -m systemd \
  -a "name=step-ca state=restarted" --become
```

### Arrêter le service

```bash
ansible -i inventory.ini step_ca_servers -m systemd \
  -a "name=step-ca state=stopped" --become
```

### Consulter les logs

```bash
ansible -i inventory.ini step_ca_servers -m shell \
  -a "journalctl -u step-ca -n 50 --no-pager" --become
```

## Mode dry-run

Pour tester le déploiement sans effectuer de changements :

```bash
ansible-playbook -i inventory.ini deploy-step-ca.yml --check
```

## Dépannage

### Erreur de connexion SSH

Si vous rencontrez des erreurs de connexion SSH :

```bash
# Vérifier la connectivité réseau
ansible -i inventory.ini step_ca_servers -m ping -vvv

# Tester SSH manuellement
ssh -vvv debian@192.168.1.100
```

### Erreur de privilèges sudo

Si vous avez des erreurs de privilèges :

```bash
# Utiliser --ask-become-pass
ansible-playbook -i inventory.ini deploy-step-ca.yml --ask-become-pass

# Ou configurer sudo sans mot de passe sur le serveur cible
echo "debian ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/debian
```

### Erreur pendant l'initialisation de la CA

Si l'initialisation échoue, vérifiez les logs :

```bash
ansible -i inventory.ini step_ca_servers -m shell \
  -a "journalctl -u step-ca -n 100 --no-pager" --become
```

### Le service ne démarre pas

```bash
# Vérifier le statut détaillé
ansible -i inventory.ini step_ca_servers -m shell \
  -a "systemctl status step-ca -l" --become

# Vérifier la configuration
ansible -i inventory.ini step_ca_servers -m shell \
  -a "step-ca validate /etc/step-ca/config/ca.json" --become
```

## Structure des fichiers après déploiement

```
/etc/step-ca/
├── config/
│   ├── ca.json              # Configuration de la CA
│   └── defaults.json        # Configuration par défaut
├── secrets/
│   ├── password.txt         # Mot de passe de la CA
│   ├── root_ca_key          # Clé privée du certificat root
│   └── intermediate_ca_key  # Clé privée du certificat intermédiaire
├── certs/
│   ├── root_ca.crt          # Certificat root
│   └── intermediate_ca.crt  # Certificat intermédiaire
└── db/                      # Base de données des certificats
```

## Sécurité

### Protéger les secrets

Utilisez Ansible Vault pour protéger les mots de passe :

```bash
# Créer un fichier vault
ansible-vault create secrets.yml

# Éditer le fichier
ansible-vault edit secrets.yml

# Utiliser le vault dans le déploiement
ansible-playbook -i inventory.ini deploy-step-ca.yml --ask-vault-pass
```

### Permissions des fichiers

Le playbook configure automatiquement les permissions :
- `/etc/step-ca/secrets/` : 700 (propriétaire uniquement)
- Fichiers dans secrets/ : 600 (lecture/écriture propriétaire uniquement)
- Utilisateur propriétaire : `step`

## Mise à jour

Pour mettre à jour step-ca vers une nouvelle version :

1. Modifiez les variables de version dans le playbook ou l'inventaire
2. Relancez le déploiement :

```bash
ansible-playbook -i inventory.ini deploy-step-ca.yml \
  -e "step_version=0.28.0" \
  -e "step_ca_version=0.28.0"
```

## Ressources

- [Documentation Ansible](https://docs.ansible.com/)
- [Documentation step-ca](https://smallstep.com/docs/step-ca)
- [GitHub step-ca](https://github.com/smallstep/certificates)

## Support

Pour toute question ou problème, consultez :
- Les logs du service : `journalctl -u step-ca -f`
- La documentation officielle step-ca
- Le repository GitHub du projet
