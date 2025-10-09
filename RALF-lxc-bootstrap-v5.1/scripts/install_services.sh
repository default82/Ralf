#!/usr/bin/env bash
set -euo pipefail

PLAN_FILE=${1:-/root/ralf/plan.json}
INVENTORY_FILE=${2:-/root/ralf/inventory.json}
MARKER="/root/ralf/state/services-installed"
LOG_DIR="/root/ralf/logs"
LOG_FILE="${LOG_DIR}/services.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "[services] Start $(date)"

if [[ -f "$MARKER" ]]; then
  echo "[services] Bereits installiert"
  exit 0
fi

for file in "$PLAN_FILE" "$INVENTORY_FILE"; do
  if [[ ! -f "$file" ]]; then
    echo "[services][ERROR] Datei fehlt: $file" >&2
    exit 1
  fi
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[services][ERROR] Kommando $1 fehlt" >&2
    exit 1
  }
}

for bin in jq pct openssl; do
  require_cmd "$bin"
done

get_field() {
  local service=$1
  local field=$2
  jq -r --arg svc "$service" --arg fld "$field" '.containers[] | select(.name==$svc) | .[$fld]' "$INVENTORY_FILE"
}

get_ctid() { get_field "$1" "ctid"; }
get_ip() { get_field "$1" "ip"; }
get_fqdn() { get_field "$1" "fqdn"; }

generate_password() {
  openssl rand -hex 16
}

DB_PASS_NETBOX=$(generate_password)
DB_PASS_N8N=$(generate_password)
DB_PASS_MATRIX=$(generate_password)
DB_PASS_GITEA=$(generate_password)

DB_IP=$(get_ip "ralf-db")
DB_CTI=$(get_ctid "ralf-db")
if [[ -z "$DB_IP" || "$DB_IP" == "unknown" ]]; then
  DB_IP="ralf-db"
fi

pct_exec() {
  local ctid=$1
  shift
  pct exec "$ctid" -- bash -lc "$*"
}

pct_push_content() {
  local ctid=$1
  local destination=$2
  local tmp
  tmp=$(mktemp)
  cat >"$tmp"
  pct push "$ctid" "$tmp" "$destination"
  rm -f "$tmp"
}

install_db() {
  echo "[services] Installiere ralf-db (CTID $DB_CTI)"
  pct_exec "$DB_CTI" "set -e; apt-get update; apt-get install -y postgresql redis-server jq"
  pct_exec "$DB_CTI" "set -e; sed -i 's/^#*listen_addresses = .*/listen_addresses = '*'/' /etc/postgresql/*/main/postgresql.conf"
  pct_exec "$DB_CTI" "set -e; echo 'host all all 0.0.0.0/0 md5' >> /etc/postgresql/*/main/pg_hba.conf"
  pct_exec "$DB_CTI" "set -e; sed -i 's/^#*bind .*/bind 0.0.0.0/' /etc/redis/redis.conf"
  pct_exec "$DB_CTI" "set -e; sed -i 's/^#*protected-mode .*/protected-mode no/' /etc/redis/redis.conf"
  pct_exec "$DB_CTI" "systemctl restart postgresql"
  pct_exec "$DB_CTI" "systemctl enable --now redis-server"
  local sql_file=$(mktemp)
  SQL_FILE="$sql_file" \
    DB_PASS_NETBOX="$DB_PASS_NETBOX" \
    DB_PASS_N8N="$DB_PASS_N8N" \
    DB_PASS_MATRIX="$DB_PASS_MATRIX" \
    DB_PASS_GITEA="$DB_PASS_GITEA" \
    python - <<'PY'
import os
from pathlib import Path

sql = f"""DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'netbox') THEN
    EXECUTE format('CREATE USER netbox WITH PASSWORD %L', '{os.environ["DB_PASS_NETBOX"]}');
  ELSE
    EXECUTE format('ALTER USER netbox WITH PASSWORD %L', '{os.environ["DB_PASS_NETBOX"]}');
  SQL_FILE="$sql_file" python - <<'PY'
import os
from pathlib import Path
sql = f"""DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'netbox') THEN
    EXECUTE format('CREATE USER netbox WITH PASSWORD %L', '{DB_PASS_NETBOX}');
  ELSE
    EXECUTE format('ALTER USER netbox WITH PASSWORD %L', '{DB_PASS_NETBOX}');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'netbox') THEN
    EXECUTE 'CREATE DATABASE netbox OWNER netbox';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n') THEN
    EXECUTE format('CREATE USER n8n WITH PASSWORD %L', '{os.environ["DB_PASS_N8N"]}');
  ELSE
    EXECUTE format('ALTER USER n8n WITH PASSWORD %L', '{os.environ["DB_PASS_N8N"]}');
    EXECUTE format('CREATE USER n8n WITH PASSWORD %L', '{DB_PASS_N8N}');
  ELSE
    EXECUTE format('ALTER USER n8n WITH PASSWORD %L', '{DB_PASS_N8N}');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'n8n') THEN
    EXECUTE 'CREATE DATABASE n8n OWNER n8n';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'synapse') THEN
    EXECUTE format('CREATE USER synapse WITH PASSWORD %L', '{os.environ["DB_PASS_MATRIX"]}');
  ELSE
    EXECUTE format('ALTER USER synapse WITH PASSWORD %L', '{os.environ["DB_PASS_MATRIX"]}');
    EXECUTE format('CREATE USER synapse WITH PASSWORD %L', '{DB_PASS_MATRIX}');
  ELSE
    EXECUTE format('ALTER USER synapse WITH PASSWORD %L', '{DB_PASS_MATRIX}');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'synapse') THEN
    EXECUTE 'CREATE DATABASE synapse OWNER synapse';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gitea') THEN
    EXECUTE format('CREATE USER gitea WITH PASSWORD %L', '{os.environ["DB_PASS_GITEA"]}');
  ELSE
    EXECUTE format('ALTER USER gitea WITH PASSWORD %L', '{os.environ["DB_PASS_GITEA"]}');
    EXECUTE format('CREATE USER gitea WITH PASSWORD %L', '{DB_PASS_GITEA}');
  ELSE
    EXECUTE format('ALTER USER gitea WITH PASSWORD %L', '{DB_PASS_GITEA}');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'gitea') THEN
    EXECUTE 'CREATE DATABASE gitea OWNER gitea';
  END IF;
END
$$;"""

Path(os.environ["SQL_FILE"]).write_text(sql)
Path(os.environ['SQL_FILE']).write_text(sql)
PY
  pct push "$DB_CTI" "$sql_file" /tmp/ralf_db_setup.sql
  rm -f "$sql_file"
  pct_exec "$DB_CTI" "su - postgres -c 'psql -f /tmp/ralf_db_setup.sql'"
}

install_gitea() {
  local ctid=$(get_ctid "ralf-gitea")
  local fqdn=$(get_fqdn "ralf-gitea")
  echo "[services] Installiere ralf-gitea (CTID $ctid)"
  pct_exec "$ctid" "set -e; apt-get update; apt-get install -y wget tar git gettext-base ca-certificates"
  pct_exec "$ctid" "id -u git >/dev/null 2>&1 || adduser --system --group --home /var/lib/gitea git"
  pct_exec "$ctid" "set -e; mkdir -p /etc/gitea /var/lib/gitea/{custom,data,log}; chown -R git:git /var/lib/gitea"
  pct_exec "$ctid" "set -e; wget -qO /usr/local/bin/gitea https://dl.gitea.com/gitea/1.21.6/gitea-1.21.6-linux-amd64 && chmod +x /usr/local/bin/gitea"
  pct_push_content "$ctid" "/etc/systemd/system/gitea.service" <<'EOS'
  pct_exec "$ctid" "cat >/etc/systemd/system/gitea.service <<'EOS'
[Unit]
Description=Gitea Service
After=network.target

[Service]
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/var/lib/gitea GITEA_WORK_DIR=/var/lib/gitea

[Install]
WantedBy=multi-user.target
EOS
  pct_push_content "$ctid" "/etc/gitea/app.ini.tmpl" <<'EOS'
EOS"
  pct_exec "$ctid" "cat >/etc/gitea/app.ini.tmpl <<'EOS'
[database]
DB_TYPE=postgres
HOST=${DB_HOST}
NAME=gitea
USER=gitea
PASSWD=${DB_PASS}
SSL_MODE=disable

[server]
DOMAIN=${FQDN}
HTTP_ADDR=0.0.0.0
HTTP_PORT=3000
ROOT_URL=https://${FQDN}/

[security]
INSTALL_LOCK=true
SECRET_KEY=${SECRET}
INTERNAL_TOKEN=${TOKEN}
EOS
  pct_exec "$ctid" "chmod 644 /etc/systemd/system/gitea.service"
EOS"
  local secret=$(generate_password)
  local token=$(generate_password)
  pct_exec "$ctid" "DB_HOST='${DB_IP}:5432' DB_PASS='${DB_PASS_GITEA}' FQDN='${fqdn}' SECRET='${secret}' TOKEN='${token}' envsubst < /etc/gitea/app.ini.tmpl > /etc/gitea/app.ini"
  pct_exec "$ctid" "chmod 600 /etc/gitea/app.ini"
  pct_exec "$ctid" "systemctl daemon-reload && systemctl enable --now gitea"
}

install_netbox() {
  local ctid=$(get_ctid "ralf-netbox")
  local fqdn=$(get_fqdn "ralf-netbox")
  local secret=$(generate_password)
  local ip=$(get_ip "ralf-netbox")
  echo "[services] Installiere ralf-netbox (CTID $ctid)"
  pct_exec "$ctid" "set -e; apt-get update; apt-get install -y python3-venv python3-pip build-essential libpq-dev libjpeg-dev zlib1g-dev nginx supervisor redis-tools gettext-base"
  pct_exec "$ctid" "id -u netbox >/dev/null 2>&1 || useradd --system --home /opt/netbox --shell /bin/bash netbox"
  pct_exec "$ctid" "set -e; mkdir -p /opt/netbox && python3 -m venv /opt/netbox/venv"
  pct_exec "$ctid" "set -e; /opt/netbox/venv/bin/pip install --upgrade pip wheel && /opt/netbox/venv/bin/pip install netbox==3.6.8 gunicorn psycopg2-binary"
  pct_push_content "$ctid" "/opt/netbox/gunicorn.py" <<'EOS'
  pct_exec "$ctid" "cat >/opt/netbox/gunicorn.py <<'EOS'
command = '/opt/netbox/venv/bin/gunicorn'
pythonpath = '/opt/netbox/venv/lib/python3.11/site-packages/netbox'
bind = '0.0.0.0:8001'
workers = 3
user = 'netbox'
EOS
  pct_push_content "$ctid" "/etc/systemd/system/netbox.service" <<'EOS'
EOS"
  pct_exec "$ctid" "cat >/etc/systemd/system/netbox.service <<'EOS'
[Unit]
Description=NetBox WSGI
After=network.target

[Service]
User=netbox
Group=netbox
WorkingDirectory=/opt/netbox
ExecStart=/opt/netbox/venv/bin/gunicorn -c /opt/netbox/gunicorn.py netbox.wsgi
Restart=always

[Install]
WantedBy=multi-user.target
EOS
  pct_push_content "$ctid" "/opt/netbox/config.tmpl" <<'EOS'
EOS"
  pct_exec "$ctid" "cat >/opt/netbox/config.tmpl <<'EOS'
DATABASE = {
    'NAME': 'netbox',
    'USER': 'netbox',
    'PASSWORD': '${DB_PASS}',
    'HOST': '${DB_HOST}',
    'PORT': '5432',
}
REDIS = {
    'caching': {
        'HOST': '${DB_HOST}',
        'PORT': 6379,
        'PASSWORD': '',
        'DATABASE': 1,
    },
    'tasks': {
        'HOST': '${DB_HOST}',
        'PORT': 6379,
        'PASSWORD': '',
        'DATABASE': 2,
    }
}
SECRET_KEY = '${SECRET}'
ALLOWED_HOSTS = ['${FQDN}', '${IP}']
EOS
  pct_exec "$ctid" "chmod 644 /etc/systemd/system/netbox.service"
  pct_exec "$ctid" "DB_PASS='${DB_PASS_NETBOX}' DB_HOST='${DB_IP}' SECRET='${secret}' FQDN='${fqdn}' IP='${ip}' envsubst < /opt/netbox/config.tmpl > /opt/netbox/local_config.py"
  pct_exec "$ctid" "systemctl daemon-reload && systemctl enable --now netbox"
  pct_push_content "$ctid" "/etc/nginx/sites-available/netbox" <<'EOS'
EOS"
  pct_exec "$ctid" "DB_PASS='${DB_PASS_NETBOX}' DB_HOST='${DB_IP}' SECRET='${secret}' FQDN='${fqdn}' IP='${ip}' envsubst < /opt/netbox/config.tmpl > /opt/netbox/local_config.py"
  pct_exec "$ctid" "systemctl daemon-reload && systemctl enable --now netbox"
  pct_exec "$ctid" "cat >/etc/nginx/sites-available/netbox <<'EOS'
server {
    listen 80;
    server_name ${FQDN};
    location / {
        proxy_pass http://127.0.0.1:8001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOS
EOS"
  pct_exec "$ctid" "FQDN='${fqdn}' envsubst < /etc/nginx/sites-available/netbox > /etc/nginx/sites-enabled/netbox"
  pct_exec "$ctid" "nginx -t"
  pct_exec "$ctid" "systemctl restart nginx"
}

install_n8n() {
  local ctid=$(get_ctid "ralf-n8n")
  echo "[services] Installiere ralf-n8n (CTID $ctid)"
  pct_exec "$ctid" "set -e; apt-get update; apt-get install -y curl gnupg"
  pct_exec "$ctid" "set -e; curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"
  pct_exec "$ctid" "set -e; apt-get install -y nodejs build-essential"
  pct_exec "$ctid" "npm install -g n8n"
  pct_push_content "$ctid" "/etc/systemd/system/n8n.service" <<'EOS'
  pct_exec "$ctid" "cat >/etc/systemd/system/n8n.service <<'EOS'
[Unit]
Description=n8n Automation
After=network.target

[Service]
Type=simple
User=root
Environment=DB_TYPE=postgresdb
Environment=DB_POSTGRESDB_HOST=${DB_HOST}
Environment=DB_POSTGRESDB_PORT=5432
Environment=DB_POSTGRESDB_DATABASE=n8n
Environment=DB_POSTGRESDB_USER=n8n
Environment=DB_POSTGRESDB_PASSWORD=${DB_PASS}
Environment=QUEUE_BULL_REDIS_HOST=${DB_HOST}
Environment=QUEUE_BULL_REDIS_PORT=6379
ExecStart=/usr/bin/n8n start
Restart=always

[Install]
WantedBy=multi-user.target
EOS
EOS"
  pct_exec "$ctid" "DB_HOST='${DB_IP}' DB_PASS='${DB_PASS_N8N}' envsubst < /etc/systemd/system/n8n.service > /etc/systemd/system/n8n.service.tmp"
  pct_exec "$ctid" "mv /etc/systemd/system/n8n.service.tmp /etc/systemd/system/n8n.service"
  pct_exec "$ctid" "systemctl daemon-reload && systemctl enable --now n8n"
}

install_synapse() {
  local ctid=$(get_ctid "ralf-matrix")
  local fqdn=$(get_fqdn "ralf-matrix")
  echo "[services] Installiere Synapse (CTID $ctid)"
  pct_exec "$ctid" "set -e; debconf-set-selections <<<\"matrix-synapse-py3 matrix-synapse-py3/server-name string ralf.local\""
  pct_exec "$ctid" "set -e; apt-get update; apt-get install -y matrix-synapse-py3 python3-psycopg2"
  pct_exec "$ctid" "set -e; sed -i \"s/^server_name: .*/server_name: ${fqdn}/\" /etc/matrix-synapse/homeserver.yaml"
  pct_exec "$ctid" "mkdir -p /etc/matrix-synapse/conf.d"
  pct_push_content "$ctid" "/etc/matrix-synapse/conf.d/database.yaml" <<'EOS'
  pct_exec "$ctid" "cat >/etc/matrix-synapse/conf.d/database.yaml <<'EOS'
database:
  name: psycopg2
  args:
    user: synapse
    password: ${DB_PASS}
    database: synapse
    host: ${DB_HOST}
    port: 5432
EOS
EOS"
  pct_exec "$ctid" "DB_PASS='${DB_PASS_MATRIX}' DB_HOST='${DB_IP}' envsubst < /etc/matrix-synapse/conf.d/database.yaml > /etc/matrix-synapse/conf.d/database.yaml.tmp"
  pct_exec "$ctid" "mv /etc/matrix-synapse/conf.d/database.yaml.tmp /etc/matrix-synapse/conf.d/database.yaml"
  pct_exec "$ctid" "systemctl enable --now matrix-synapse"
}

install_vaultwarden() {
  local ctid=$(get_ctid "ralf-secrets")
  echo "[services] Installiere Vaultwarden (CTID $ctid)"
  pct_exec "$ctid" "set -e; apt-get update; apt-get install -y wget unzip"
  pct_exec "$ctid" "set -e; mkdir -p /opt/vaultwarden && cd /opt/vaultwarden && wget -qO vaultwarden.zip https://github.com/dani-garcia/vaultwarden/releases/download/1.29.2/vaultwarden-1.29.2-x86_64-unknown-linux-gnu.zip && unzip -o vaultwarden.zip && chmod +x vaultwarden"
  pct_push_content "$ctid" "/etc/systemd/system/vaultwarden.service" <<'EOS'
  pct_exec "$ctid" "cat >/etc/systemd/system/vaultwarden.service <<'EOS'
[Unit]
Description=Vaultwarden
After=network.target

[Service]
Environment=ROCKET_PORT=8080
ExecStart=/opt/vaultwarden/vaultwarden
WorkingDirectory=/opt/vaultwarden
Restart=always

[Install]
WantedBy=multi-user.target
EOS
EOS"
  pct_exec "$ctid" "systemctl daemon-reload && systemctl enable --now vaultwarden"
}

install_foreman() {
  local ctid=$(get_ctid "ralf-foreman")
  local mode=$(jq -r '.pxe.mode' "$PLAN_FILE")
  local vlan=$(jq -r '.pxe.discovery_vlan' "$PLAN_FILE")
  echo "[services] Installiere Foreman (CTID $ctid) Modus $mode"
  pct_exec "$ctid" "set -e; apt-get update; apt-get install -y ca-certificates curl gnupg"
  pct_exec "$ctid" "set -e; curl https://deb.theforeman.org/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/foreman.gpg"
  pct_exec "$ctid" "set -e; echo 'deb [signed-by=/usr/share/keyrings/foreman.gpg] https://deb.theforeman.org/ bookworm 3.9' >/etc/apt/sources.list.d/foreman.list"
  pct_exec "$ctid" "set -e; apt-get update; apt-get install -y foreman-installer"
  local dhcp="--foreman-proxy-dhcp false"
  if [[ "$mode" == "foreman_dhcp" ]]; then
    dhcp="--foreman-proxy-dhcp true --foreman-proxy-dhcp-interface=eth0"
  fi
  local tftp="--foreman-proxy-tftp false"
  if [[ "$mode" != "disabled" ]]; then
    tftp="--foreman-proxy-tftp true --foreman-proxy-dns true"
  fi
  pct_exec "$ctid" "set -e; foreman-installer --enable-foreman-proxy $dhcp $tftp --foreman-proxy-httpboot true --foreman-proxy-dhcp-managed=false || true"
  pct_exec "$ctid" "echo ${vlan} > /root/discovery_vlan"
}

write_links() {
  local links="/root/ralf/links.txt"
  echo "[services] Schreibe Links nach $links"
  {
    echo "RALF Stack Links"
    echo "================"
    jq -r '.containers[] | "- " + .name + " (" + .exposure + ") -> " + .fqdn + " [" + .ip + "]"' "$INVENTORY_FILE"
  } > "$links"
}

install_db
install_gitea
install_netbox
install_n8n
install_synapse
install_vaultwarden
install_foreman
write_links

cat <<EOF > /root/ralf/secrets/db.env
POSTGRES_HOST=${DB_IP}
POSTGRES_PORT=5432
NETBOX_DB=netbox
NETBOX_USER=netbox
NETBOX_PASSWORD=${DB_PASS_NETBOX}
N8N_DB=n8n
N8N_USER=n8n
N8N_PASSWORD=${DB_PASS_N8N}
SYNAPSE_DB=synapse
SYNAPSE_USER=synapse
SYNAPSE_PASSWORD=${DB_PASS_MATRIX}
GITEA_DB=gitea
GITEA_USER=gitea
GITEA_PASSWORD=${DB_PASS_GITEA}
EOF
chmod 600 /root/ralf/secrets/db.env

touch "$MARKER"

echo "[services] Fertig"
