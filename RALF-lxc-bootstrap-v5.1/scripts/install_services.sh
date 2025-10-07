#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

PLAN=""
INV=""
SECDIR=""
LINKS_FILE=""
PLAN="/root/ralf/plan.json"
INV="/root/ralf/inventory.json"
SECDIR="/root/ralf/secrets"
mkdir -p "$SECDIR"

req(){ command -v "$1" >/dev/null 2>&1 || { echo "Fehlt: $1"; exit 1; }; }
pw(){ tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24; echo; }

ctid_of(){ jq -r ".services[\"$1\"].ctid" "$PLAN"; }
ip_of(){ jq -r --arg n "$1" '.[$n].ip // empty' "$INV"; }

ensure_inv(){ [[ -f "$INV" ]] || { echo "Inventar fehlt: $INV"; exit 1; }; }

gen_db_pw(){
  export PG_SUPER_PASS="$(pw)"
  export PG_NETBOX_PASS="$(pw)"
  export PG_N8N_PASS="$(pw)"
  export PG_MATRIX_PASS="$(pw)"
  export PG_GITEA_PASS="$(pw)"
  cat > "$SECDIR/db.env" <<EOF_DB
PGHOST=$(ip_of ralf-db)
PGPORT=5432
PGUSER=postgres
PGPASSWORD=${PG_SUPER_PASS}

NETBOX_DB=netbox
NETBOX_USER=netbox
NETBOX_PASS=${PG_NETBOX_PASS}

N8N_DB=n8n
N8N_USER=n8n
N8N_PASS=${PG_N8N_PASS}

MATRIX_DB=synapse
MATRIX_USER=synapse
MATRIX_PASS=${PG_MATRIX_PASS}

GITEA_DB=gitea
GITEA_USER=gitea
GITEA_PASS=${PG_GITEA_PASS}
EOF_DB
}

setup_db(){
  local ct=$(ctid_of ralf-db)
  echo "[*] ralf-db (#$ct): PostgreSQL + Redis"
  pct exec "$ct" -- bash -lc "apt-get update -y && apt-get install -y postgresql redis-server"
  pct exec "$ct" -- bash -lc "systemctl enable --now postgresql redis-server"
  pct exec "$ct" -- bash -lc "sudo -u postgres psql -c \"ALTER USER postgres WITH PASSWORD '${PG_SUPER_PASS}';\""
  pct exec "$ct" -- bash -lc "sudo -u postgres psql -tc \"SELECT 1 FROM pg_database WHERE datname='netbox'\" | grep -q 1 || sudo -u postgres createdb netbox"
  pct exec "$ct" -- bash -lc "sudo -u postgres psql -c \"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='netbox') THEN CREATE USER netbox WITH PASSWORD '${PG_NETBOX_PASS}'; END IF; END $$; GRANT ALL PRIVILEGES ON DATABASE netbox TO netbox;\""
  pct exec "$ct" -- bash -lc "sudo -u postgres psql -tc \"SELECT 1 FROM pg_database WHERE datname='n8n'\" | grep -q 1 || sudo -u postgres createdb n8n"
  pct exec "$ct" -- bash -lc "sudo -u postgres psql -c \"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='n8n') THEN CREATE USER n8n WITH PASSWORD '${PG_N8N_PASS}'; END IF; END $$; GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;\""
  pct exec "$ct" -- bash -lc "sudo -u postgres psql -tc \"SELECT 1 FROM pg_database WHERE datname='synapse'\" | grep -q 1 || sudo -u postgres createdb synapse"
  pct exec "$ct" -- bash -lc "sudo -u postgres psql -c \"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='synapse') THEN CREATE USER synapse WITH PASSWORD '${PG_MATRIX_PASS}'; END IF; END $$; GRANT ALL PRIVILEGES ON DATABASE synapse TO synapse;\""
  pct exec "$ct" -- bash -lc "sudo -u postgres psql -tc \"SELECT 1 FROM pg_database WHERE datname='gitea'\" | grep -q 1 || sudo -u postgres createdb gitea"
  pct exec "$ct" -- bash -lc "sudo -u postgres psql -c \"DO $$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='gitea') THEN CREATE USER gitea WITH PASSWORD '${PG_GITEA_PASS}'; END IF; END $$; GRANT ALL PRIVILEGES ON DATABASE gitea TO gitea;\""
}

install_gitea(){
  local ct=$(ctid_of ralf-gitea)
  local ipdb=$(ip_of ralf-db)
  echo "[*] ralf-gitea (#$ct): Gitea"
  pct exec "$ct" -- bash -lc "apt-get update -y && apt-get install -y wget tar adduser"
  pct exec "$ct" -- bash -lc "useradd -m -r -d /var/lib/gitea -s /bin/bash git || true"
  pct exec "$ct" -- bash -lc "mkdir -p /etc/gitea /var/lib/gitea/custom /var/lib/gitea/data /var/log/gitea && chown -R git:git /var/lib/gitea /var/log/gitea"
  pct exec "$ct" -- bash -lc "wget -qO /usr/local/bin/gitea https://dl.gitea.com/gitea/1.22.0/gitea-1.22.0-linux-amd64 && chmod +x /usr/local/bin/gitea"
  pct exec "$ct" -- bash -lc "cat >/etc/gitea/app.ini <<EOF_APP
[server]
DOMAIN = $(ip_of ralf-gitea)
HTTP_ADDR = 0.0.0.0
HTTP_PORT = 3000
[database]
DB_TYPE = postgres
HOST = ${ipdb}:5432
NAME = gitea
USER = gitea
PASSWD = ${PG_GITEA_PASS}
SSL_MODE = disable
[security]
INSTALL_LOCK = true
SECRET_KEY = $(tr -dc A-Za-z0-9 < /dev/urandom | head -c 32)
EOF_APP"
  pct exec "$ct" -- bash -lc "cat >/etc/systemd/system/gitea.service <<'SVC'
[Unit]
Description=Gitea
After=network.target
[Service]
User=git
Group=git
WorkingDirectory=/var/lib/gitea/
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/var/lib/gitea GITEA_WORK_DIR=/var/lib/gitea
[Install]
WantedBy=multi-user.target
SVC"
  pct exec "$ct" -- bash -lc "systemctl daemon-reload && systemctl enable --now gitea"
}

install_netbox(){
  local ct=$(ctid_of ralf-netbox)
  local ipdb=$(ip_of ralf-db)
  echo "[*] ralf-netbox (#$ct): NetBox"
  pct exec "$ct" -- bash -lc "apt-get update -y && apt-get install -y python3-venv python3-pip python3-dev postgresql-client redis-server nginx git"
  pct exec "$ct" -- bash -lc "adduser --system --group netbox || true"
  pct exec "$ct" -- bash -lc "mkdir -p /opt/netbox && chown netbox:netbox /opt/netbox"
  pct exec "$ct" -- bash -lc "git clone --depth=1 https://github.com/netbox-community/netbox.git /opt/netbox || true"
  pct exec "$ct" -- bash -lc "cd /opt/netbox && python3 -m venv venv && . venv/bin/activate && pip install -U pip wheel && pip install -r requirements.txt"
  pct exec "$ct" -- bash -lc "cp /opt/netbox/netbox/netbox/configuration_example.py /opt/netbox/netbox/netbox/configuration.py"
  pct exec "$ct" -- bash -lc "sed -i \"s/'NAME': 'netbox'/'NAME': 'netbox'/\" /opt/netbox/netbox/netbox/configuration.py"
  pct exec "$ct" -- bash -lc "sed -i \"s/'USER': ''/'USER': 'netbox'/\" /opt/netbox/netbox/netbox/configuration.py"
  pct exec "$ct" -- bash -lc "sed -i \"s/'PASSWORD': ''/'PASSWORD': '${PG_NETBOX_PASS}'/\" /opt/netbox/netbox/netbox/configuration.py"
  pct exec "$ct" -- bash -lc "sed -i \"s/'HOST': 'localhost'/'HOST': '${ipdb}'/\" /opt/netbox/netbox/netbox/configuration.py"
  pct exec "$ct" -- bash -lc "sed -i \"s/ALLOWED_HOSTS = \\[\\]/ALLOWED_HOSTS = ['*']/\" /opt/netbox/netbox/netbox/configuration.py"
  pct exec "$ct" -- bash -lc "cd /opt/netbox && . venv/bin/activate && python3 netbox/manage.py migrate && python3 netbox/generate_secret_key.py > /opt/netbox/netbox/netbox/secret.txt"
  pct exec "$ct" -- bash -lc "cd /opt/netbox && . venv/bin/activate && python3 netbox/manage.py createsuperuser --noinput || true"
  pct exec "$ct" -- bash -lc "cat >/etc/systemd/system/netbox.service <<'SVC'
[Unit]
Description=NetBox WSGI Service
After=network.target
[Service]
Type=simple
User=netbox
Group=netbox
WorkingDirectory=/opt/netbox
ExecStart=/opt/netbox/venv/bin/gunicorn --workers 3 --bind 0.0.0.0:8001 netbox.wsgi
Restart=on-failure
[Install]
WantedBy=multi-user.target
SVC"
  pct exec "$ct" -- bash -lc "systemctl daemon-reload && systemctl enable --now netbox"
  pct exec "$ct" -- bash -lc "cat >/etc/nginx/sites-available/netbox <<'NG'
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:8001;
    }
}
NG
ln -sf /etc/nginx/sites-available/netbox /etc/nginx/sites-enabled/netbox
systemctl restart nginx"
}

install_n8n(){
  local ct=$(ctid_of ralf-n8n)
  local ipdb=$(ip_of ralf-db)
  echo "[*] ralf-n8n (#$ct): n8n"
  pct exec "$ct" -- bash -lc "apt-get update -y && apt-get install -y curl gnupg"
  pct exec "$ct" -- bash -lc "curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && apt-get install -y nodejs"
  pct exec "$ct" -- bash -lc "npm install -g n8n"
  pct exec "$ct" -- bash -lc "useradd -m -r -s /bin/bash n8n || true"
  pct exec "$ct" -- bash -lc "mkdir -p /etc/n8n && chown -R n8n:n8n /etc/n8n"
  pct exec "$ct" -- bash -lc "cat >/etc/n8n/.env <<EOF_N8N
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=${ipdb}
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=${PG_N8N_PASS}
EOF_N8N"
  pct exec "$ct" -- bash -lc "cat >/etc/systemd/system/n8n.service <<'SVC'
[Unit]
Description=n8n
After=network.target
[Service]
Type=simple
User=n8n
EnvironmentFile=/etc/n8n/.env
ExecStart=/usr/bin/n8n
Restart=always
[Install]
WantedBy=multi-user.target
SVC"
  pct exec "$ct" -- bash -lc "systemctl daemon-reload && systemctl enable --now n8n"
}

install_matrix(){
  local ct=$(ctid_of ralf-matrix)
  local ipdb=$(ip_of ralf-db)
  echo "[*] ralf-matrix (#$ct): Synapse"
  pct exec "$ct" -- bash -lc "apt-get update -y && apt-get install -y matrix-synapse-py3 python3-psycopg2"
  pct exec "$ct" -- bash -lc "sed -i \"s/^#database:/database:/\" /etc/matrix-synapse/homeserver.yaml"
  pct exec "$ct" -- bash -lc "awk '/^database:/{print;print \"  name: psycopg2\\n  args:\\n    user: synapse\\n    password: '${PG_MATRIX_PASS}'\\n    database: synapse\\n    host: '${ipdb}'\\n    cp_min: 5\\n    cp_max: 10\";next}1' /etc/matrix-synapse/homeserver.yaml > /etc/matrix-synapse/homeserver.yaml.new && mv /etc/matrix-synapse/homeserver.yaml.new /etc/matrix-synapse/homeserver.yaml"
  pct exec "$ct" -- bash -lc "sed -i \"s/^server_name:.*/server_name: ralf.local/\" /etc/matrix-synapse/homeserver.yaml"
  pct exec "$ct" -- bash -lc "systemctl enable --now matrix-synapse"
}

install_vaultwarden(){
  local ct=$(ctid_of ralf-secrets)
  echo "[*] ralf-secrets (#$ct): Vaultwarden"
  pct exec "$ct" -- bash -lc "apt-get update -y && apt-get install -y wget jq"
  pct exec "$ct" -- bash -lc "useradd -m -r -s /bin/false vaultwarden || true"
  pct exec "$ct" -- bash -lc "mkdir -p /opt/vaultwarden /var/lib/vaultwarden && chown vaultwarden:vaultwarden /var/lib/vaultwarden"
  pct exec "$ct" -- bash -lc "wget -qO /opt/vaultwarden/vaultwarden https://github.com/dani-garcia/vaultwarden/releases/download/1.30.5/vaultwarden-x86_64-unknown-linux-gnu && chmod +x /opt/vaultwarden/vaultwarden"
  pct exec "$ct" -- bash -lc "cat >/etc/systemd/system/vaultwarden.service <<'SVC'
[Unit]
Description=Vaultwarden
After=network.target
[Service]
User=vaultwarden
Group=vaultwarden
ExecStart=/opt/vaultwarden/vaultwarden
Environment=ROCKET_PORT=8080
Environment=DATA_FOLDER=/var/lib/vaultwarden
Restart=always
[Install]
WantedBy=multi-user.target
SVC"
  pct exec "$ct" -- bash -lc "systemctl daemon-reload && systemctl enable --now vaultwarden"
}

install_foreman(){
  local ct=$(ctid_of ralf-foreman)
  local mode=$(jq -r '.pxe.mode' "$PLAN")
  echo "[*] ralf-foreman (#$ct): Foreman PXE Modus: ${mode}"
  pct exec "$ct" -- bash -lc "apt-get update -y && apt-get install -y ca-certificates curl gnupg"
  pct exec "$ct" -- bash -lc "echo 'deb http://deb.theforeman.org/ bookworm 3.x' > /etc/apt/sources.list.d/foreman.list"
  pct exec "$ct" -- bash -lc "curl -fsSL https://deb.theforeman.org/pubkey.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/foreman.gpg"
  pct exec "$ct" -- bash -lc "apt-get update -y && apt-get install -y foreman-installer"
  if [[ "$mode" == "foreman_dhcp" ]]; then
    pct exec "$ct" -- bash -lc "foreman-installer --foreman-proxy-tftp=true --foreman-proxy-httpboot=true --foreman-proxy-dhcp=true --foreman-proxy-dns=false"
  elif [[ "$mode" == "router_relay" ]]; then
    pct exec "$ct" -- bash -lc "foreman-installer --foreman-proxy-tftp=true --foreman-proxy-httpboot=true --foreman-proxy-dhcp=false --foreman-proxy-dns=false"
  else
    pct exec "$ct" -- bash -lc "foreman-installer --foreman-proxy-tftp=false --foreman-proxy-httpboot=false --foreman-proxy-dhcp=false --foreman-proxy-dns=false"
  fi
}

write_links(){
  mkdir -p "$(dirname "$LINKS_FILE")"
  cat > "$LINKS_FILE" <<EOF_LINKS
  local f="/root/ralf/links.txt"
  cat > "$f" <<EOF_LINKS
=== RALF Dienste ===
Edge (Caddy):             http://$(ip_of ralf-edge) (80/443 ggf. via FQDN)
KI (ralf-ki):             http://$(ip_of ralf-ki):11434    (Ollama) | vLLM ggf.: http://$(ip_of ralf-ki):8000/v1
Gitea:                    http://$(ip_of ralf-gitea):3000
NetBox:                   http://$(ip_of ralf-netbox)
n8n:                      http://$(ip_of ralf-n8n):5678
Matrix Synapse:           http://$(ip_of ralf-matrix):8008
Vaultwarden:              http://$(ip_of ralf-secrets):8080
Foreman:                  https://$(ip_of ralf-foreman)

Plan:    $PLAN
Secrets: $SECDIR/
Inventar:$INV
EOF_LINKS
  echo "[*] Summary: $LINKS_FILE"; cat "$LINKS_FILE"
}

main(){
  req jq
  PLAN=$(jq -r '.plan_path' "$CONFIG_FILE")
  INV=$(jq -r '.inventory_path' "$CONFIG_FILE")
  SECDIR=$(jq -r '.secrets_dir' "$CONFIG_FILE")
  LINKS_FILE=$(jq -r '.links_path' "$CONFIG_FILE")
  mkdir -p "$SECDIR"
  ensure_inv
  gen_db_pw
Plan:    /root/ralf/plan.json
Secrets: /root/ralf/secrets/
Inventar:/root/ralf/inventory.json
EOF_LINKS
  echo "[*] Summary: $f"; cat "$f"
}

main(){
  req jq; ensure_inv; gen_db_pw
  setup_db
  install_gitea
  install_netbox
  install_n8n
  install_matrix
  install_vaultwarden
  install_foreman
  write_links
}
main "$@"
