# Configuration Reverse Proxy pour step-ca

Ce guide explique comment configurer step-ca derrière un reverse proxy (Nginx, Caddy, Traefik, HAProxy).

## Pourquoi utiliser un reverse proxy ?

- **Centralisation SSL/TLS** : Un seul point de gestion des certificats externes
- **Load balancing** : Répartir la charge entre plusieurs instances step-ca
- **Sécurité renforcée** : Isolation de step-ca du réseau externe
- **Logging centralisé** : Logs d'accès au niveau du proxy
- **Rate limiting** : Contrôle du trafic au niveau du proxy

## Installation avec reverse proxy

### Variables d'environnement

```bash
# Installation standard (exposition directe)
CA_DNS_NAME=ca.exemple.com ./install-step-ca.sh

# Installation derrière reverse proxy (bind localhost)
BEHIND_REVERSE_PROXY=true CA_DNS_NAME=ca.exemple.com ./install-step-ca.sh

# Configuration personnalisée
BEHIND_REVERSE_PROXY=true \
BIND_ADDRESS=127.0.0.1 \
CA_DNS_NAME=ca.exemple.com \
CA_PORT=9000 \
./install-step-ca.sh
```

**Variables disponibles** :
- `BEHIND_REVERSE_PROXY` : `true` pour activer le mode reverse proxy (bind sur localhost)
- `BIND_ADDRESS` : Adresse d'écoute (défaut: `0.0.0.0` ou `127.0.0.1` si reverse proxy)
- `CA_DNS_NAME` : Nom de domaine public de la CA
- `CA_PORT` : Port d'écoute de step-ca (défaut: 9000)

## Configuration Nginx

### Configuration minimale

```nginx
upstream step-ca-backend {
    server 127.0.0.1:9000;
}

server {
    listen 443 ssl http2;
    server_name ca.exemple.com;

    # Certificats SSL du reverse proxy
    ssl_certificate /etc/nginx/ssl/ca.exemple.com.crt;
    ssl_certificate_key /etc/nginx/ssl/ca.exemple.com.key;

    # Configuration SSL recommandée
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass https://step-ca-backend;

        # Headers requis
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Configuration SSL pour le backend
        proxy_ssl_verify off;  # Désactiver si certificat auto-signé
        # OU avec vérification :
        # proxy_ssl_trusted_certificate /etc/step-ca/authorities/default/certs/root_ca.crt;
        # proxy_ssl_verify on;

        # HTTP version
        proxy_http_version 1.1;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# Redirection HTTP vers HTTPS
server {
    listen 80;
    server_name ca.exemple.com;
    return 301 https://$server_name$request_uri;
}
```

### Configuration avec client certificates

```nginx
server {
    listen 443 ssl http2;
    server_name ca.exemple.com;

    ssl_certificate /etc/nginx/ssl/ca.exemple.com.crt;
    ssl_certificate_key /etc/nginx/ssl/ca.exemple.com.key;

    # Authentification par certificat client (optionnel)
    ssl_client_certificate /etc/nginx/ssl/ca-chain.pem;
    ssl_verify_client optional;

    location / {
        proxy_pass https://127.0.0.1:9000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-SSL-Client-Cert $ssl_client_cert;

        proxy_ssl_verify off;
        proxy_http_version 1.1;
    }
}
```

### Tester la configuration Nginx

```bash
# Vérifier la configuration
sudo nginx -t

# Recharger Nginx
sudo systemctl reload nginx

# Vérifier les logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

## Configuration Caddy

Caddy est très simple à configurer et gère automatiquement les certificats Let's Encrypt.

### Caddyfile

```caddy
ca.exemple.com {
    reverse_proxy localhost:9000 {
        transport http {
            tls_insecure_skip_verify
            # OU avec vérification :
            # tls_trusted_ca_certs /etc/step-ca/authorities/default/certs/root_ca.crt
        }
    }

    # Logs
    log {
        output file /var/log/caddy/ca.exemple.com.log
        format json
    }
}
```

### Configuration avec rate limiting

```caddy
ca.exemple.com {
    # Rate limiting (100 req/min par IP)
    rate_limit {
        zone ca_zone {
            key {remote_host}
            events 100
            window 1m
        }
    }

    reverse_proxy localhost:9000 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
```

### Tester la configuration Caddy

```bash
# Vérifier la configuration
caddy validate --config /etc/caddy/Caddyfile

# Recharger Caddy
sudo systemctl reload caddy

# Voir les logs
sudo journalctl -u caddy -f
```

## Configuration Traefik

Traefik utilise des labels Docker ou des fichiers de configuration.

### Configuration avec fichier YAML

**traefik.yml** :
```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  file:
    filename: /etc/traefik/dynamic.yml

certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@exemple.com
      storage: /etc/traefik/acme.json
      httpChallenge:
        entryPoint: web
```

**dynamic.yml** :
```yaml
http:
  routers:
    step-ca:
      rule: "Host(`ca.exemple.com`)"
      service: step-ca-service
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt

  services:
    step-ca-service:
      loadBalancer:
        servers:
          - url: "https://127.0.0.1:9000"
        serversTransport: insecureTransport

  serversTransports:
    insecureTransport:
      insecureSkipVerify: true
```

### Configuration avec Docker Compose

```yaml
version: '3'

services:
  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=admin@exemple.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./letsencrypt:/letsencrypt"
    labels:
      - "traefik.http.routers.step-ca.rule=Host(`ca.exemple.com`)"
      - "traefik.http.routers.step-ca.entrypoints=websecure"
      - "traefik.http.routers.step-ca.tls.certresolver=letsencrypt"
      - "traefik.http.services.step-ca.loadbalancer.server.url=https://host.docker.internal:9000"
      - "traefik.http.services.step-ca.loadbalancer.serversTransport=insecureTransport"
```

## Configuration HAProxy

### haproxy.cfg

```haproxy
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

    # SSL/TLS
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000

frontend step-ca-front
    bind *:443 ssl crt /etc/haproxy/certs/ca.exemple.com.pem
    mode http

    # Headers
    http-request set-header X-Forwarded-Proto https
    http-request set-header X-Forwarded-For %[src]

    default_backend step-ca-backend

frontend http-redirect
    bind *:80
    mode http
    redirect scheme https code 301

backend step-ca-backend
    mode http
    balance roundrobin

    # Backend SSL
    server step-ca1 127.0.0.1:9000 ssl verify none check

    # OU avec vérification :
    # server step-ca1 127.0.0.1:9000 ssl ca-file /etc/step-ca/authorities/default/certs/root_ca.crt verify required check
```

### Tester HAProxy

```bash
# Vérifier la configuration
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

# Recharger HAProxy
sudo systemctl reload haproxy

# Voir les stats
curl http://localhost:9000/haproxy?stats
```

## Configuration step-ca pour reverse proxy

### Modifier ca.json manuellement

Si step-ca est déjà installé, vous pouvez modifier `/etc/step-ca/authorities/default/config/ca.json` :

```json
{
  "address": "127.0.0.1:9000",
  "dnsNames": ["ca.exemple.com"],
  ...
}
```

Puis redémarrer le service :
```bash
sudo systemctl restart step-ca
```

## Vérification et tests

### Vérifier que step-ca écoute sur localhost

```bash
sudo netstat -tlnp | grep 9000
# Devrait montrer : 127.0.0.1:9000
```

### Tester l'accès via le reverse proxy

```bash
# Health check
curl -k https://ca.exemple.com/health

# Récupérer les certificats root
curl -k https://ca.exemple.com/roots.pem

# Tester avec step CLI
step ca health --ca-url https://ca.exemple.com
```

### Tester ACME

```bash
# Avec certbot
certbot certonly \
  --standalone \
  --server https://ca.exemple.com/acme/acme/directory \
  -d test.exemple.com

# Avec step CLI
step ca certificate test.exemple.com test.crt test.key \
  --ca-url https://ca.exemple.com
```

## Dépannage

### Le proxy ne peut pas se connecter à step-ca

```bash
# Vérifier que step-ca écoute
sudo systemctl status step-ca
sudo journalctl -u step-ca -n 50

# Vérifier les ports
sudo netstat -tlnp | grep 9000

# Vérifier les logs du proxy
# Nginx
sudo tail -f /var/log/nginx/error.log

# Caddy
sudo journalctl -u caddy -f

# HAProxy
sudo tail -f /var/log/haproxy.log
```

### Erreurs de certificat

```bash
# Vérifier le certificat step-ca
openssl s_client -connect 127.0.0.1:9000 -showcerts

# Récupérer le certificat root pour le proxy
sudo cp /etc/step-ca/authorities/default/certs/root_ca.crt \
  /etc/nginx/ssl/step-ca-root.crt
```

### Erreurs ACME

Les clients ACME doivent pouvoir accéder à `/.well-known/acme-challenge/`. Assurez-vous que le reverse proxy transmet correctement ces requêtes.

## Haute disponibilité

### Load balancing avec plusieurs instances

**Nginx** :
```nginx
upstream step-ca-cluster {
    least_conn;
    server 10.0.0.1:9000 max_fails=3 fail_timeout=30s;
    server 10.0.0.2:9000 max_fails=3 fail_timeout=30s;
    server 10.0.0.3:9000 max_fails=3 fail_timeout=30s;
}

server {
    listen 443 ssl http2;
    server_name ca.exemple.com;

    location / {
        proxy_pass https://step-ca-cluster;
        # ... reste de la configuration
    }
}
```

**Note** : Pour la haute disponibilité, step-ca nécessite une base de données partagée (MySQL, PostgreSQL, etc.) au lieu de la base de données locale par défaut.

## Sécurité

### Bonnes pratiques

1. **Isoler step-ca** : Utilisez toujours `127.0.0.1` comme bind address
2. **Certificats séparés** : Utilisez des certificats différents pour le proxy et step-ca
3. **Firewall** : Bloquez l'accès direct au port 9000 depuis l'extérieur
4. **Rate limiting** : Activez la limitation de débit au niveau du proxy
5. **Monitoring** : Surveillez les logs du proxy et de step-ca
6. **Mises à jour** : Maintenez le proxy et step-ca à jour

### Exemple de règles firewall (iptables)

```bash
# Autoriser localhost vers step-ca
sudo iptables -A INPUT -i lo -p tcp --dport 9000 -j ACCEPT

# Bloquer l'accès externe direct à step-ca
sudo iptables -A INPUT -p tcp --dport 9000 -j DROP

# Autoriser HTTPS vers le reverse proxy
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
```

## Ressources

- [Documentation step-ca](https://smallstep.com/docs/step-ca)
- [Nginx Reverse Proxy](https://docs.nginx.com/nginx/admin-guide/web-server/reverse-proxy/)
- [Caddy Reverse Proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [HAProxy Configuration Manual](http://www.haproxy.org/#docs)
