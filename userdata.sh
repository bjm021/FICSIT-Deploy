#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/satisfactory-setup.log) 2>&1

echo "=== Satisfactory Dedicated Server bootstrap ==="

# ---------------------------------------------------------------------------
# System setup
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  lib32gcc-s1 \
  curl \
  wget \
  unzip \
  htop \
  screen \
  python3

# ---------------------------------------------------------------------------
# Create a dedicated non-root user
# ---------------------------------------------------------------------------
if ! id -u steam &>/dev/null; then
  useradd -m -s /bin/bash steam
fi

# ---------------------------------------------------------------------------
# Install SteamCMD
# ---------------------------------------------------------------------------
mkdir -p /home/steam/steamcmd
cd /home/steam/steamcmd

curl -sSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
  | tar -xz

chown -R steam:steam /home/steam/steamcmd

# ---------------------------------------------------------------------------
# Install Satisfactory Dedicated Server (App ID 1690800)
# ---------------------------------------------------------------------------
INSTALL_DIR="/home/steam/satisfactory"
mkdir -p "$INSTALL_DIR"
chown -R steam:steam "$INSTALL_DIR"

sudo -u steam /home/steam/steamcmd/steamcmd.sh \
  +force_install_dir "$INSTALL_DIR" \
  +login ${steam_user} \
  +app_update 1690800 validate \
  +quit

# ---------------------------------------------------------------------------
# systemd service
# ---------------------------------------------------------------------------
cat > /etc/systemd/system/satisfactory.service << 'EOF'
[Unit]
Description=Satisfactory Dedicated Server
After=network.target

[Service]
Type=simple
User=steam
Group=steam
WorkingDirectory=/home/steam/satisfactory
ExecStart=/home/steam/satisfactory/FactoryServer.sh \
  -Port=7777 \
  -ReliablePort=8888 \
  -multihome=0.0.0.0 \
  -log \
  -unattended

Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=satisfactory

# Give the server enough time to autosave before stopping
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable satisfactory
systemctl start satisfactory

# ---------------------------------------------------------------------------
# Install rclone
# ---------------------------------------------------------------------------
curl -fsSL https://rclone.org/install.sh | bash

# ---------------------------------------------------------------------------
# Write credentials config (values injected by Terraform at deploy time)
# ---------------------------------------------------------------------------
mkdir -p /etc/satisfactory
chmod 700 /etc/satisfactory

cat > /etc/satisfactory/config << EOF
SF_SERVER_NAME="${sf_server_name}"
SF_ADMIN_PASSWORD="${sf_admin_password}"
R2_ACCOUNT_ID="${r2_account_id}"
R2_ACCESS_KEY_ID="${r2_access_key_id}"
R2_SECRET_ACCESS_KEY="${r2_secret_access_key}"
R2_BUCKET_NAME="${r2_bucket_name}"
R2_JURISDICTION="${r2_jurisdiction}"
EOF
chmod 600 /etc/satisfactory/config

# ---------------------------------------------------------------------------
# claim.sh — runs once on first boot to set server name + admin password
# ---------------------------------------------------------------------------
cat > /usr/local/bin/satisfactory-claim.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
exec >> /var/log/satisfactory-claim.log 2>&1

. /etc/satisfactory/config

if [ -f /etc/satisfactory/claimed ]; then
  echo "$(date -u): Already claimed, skipping."
  exit 0
fi

SERVER="https://localhost:7777"
echo "$(date -u): Waiting for Satisfactory server API..."

for i in $(seq 1 60); do
  if curl -skf -X POST "$SERVER/api/v1" \
      -H "Content-Type: application/json" \
      -d '{"function":"HealthCheck","data":{"ClientCustomData":""}}' \
      | grep -q '"health"'; then
    echo "$(date -u): Server API is up."
    break
  fi
  echo "$(date -u): Attempt $i/60, retrying in 5s..."
  sleep 5
  if [ "$i" -eq 60 ]; then
    echo "$(date -u): ERROR: Server did not respond within 5 minutes."
    exit 1
  fi
done

echo "$(date -u): Performing PasswordlessLogin..."
RESPONSE=$(curl -sk -X POST "$SERVER/api/v1" \
  -H "Content-Type: application/json" \
  -d '{"function":"PasswordlessLogin","data":{"MinimumPrivilegeLevel":"InitialAdmin"}}')

TOKEN=$(echo "$RESPONSE" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d['data']['authenticationToken'])" 2>/dev/null || true)

if [ -z "$TOKEN" ]; then
  echo "$(date -u): PasswordlessLogin failed — server may already be claimed: $RESPONSE"
  touch /etc/satisfactory/claimed
  exit 0
fi

echo "$(date -u): Claiming server as '$SF_SERVER_NAME'..."
CLAIM=$(curl -sk -X POST "$SERVER/api/v1" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"function\":\"ClaimServer\",\"data\":{\"ServerName\":\"$SF_SERVER_NAME\",\"AdminPassword\":\"$SF_ADMIN_PASSWORD\"}}")

if echo "$CLAIM" | grep -q '"authenticationToken"'; then
  echo "$(date -u): Server claimed successfully."
  touch /etc/satisfactory/claimed
else
  echo "$(date -u): ERROR: ClaimServer failed: $CLAIM"
  exit 1
fi
SCRIPT
chmod +x /usr/local/bin/satisfactory-claim.sh

# ---------------------------------------------------------------------------
# backup.sh — authenticate, trigger save, upload to R2, prune old backups
# ---------------------------------------------------------------------------
cat > /usr/local/bin/satisfactory-backup.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
exec >> /var/log/satisfactory-backup.log 2>&1

. /etc/satisfactory/config

SAVES_DIR="/home/steam/.config/Epic/FactoryGame/Saved/SaveGames/server"
SERVER="https://localhost:7777"
RCLONE_CONF=/etc/satisfactory/rclone.conf
KEEP=3

echo "$(date -u): Starting backup..."

# ---- Authenticate ----
RESPONSE=$(curl -sk -X POST "$SERVER/api/v1" \
  -H "Content-Type: application/json" \
  -d "{\"function\":\"PasswordLogin\",\"data\":{\"MinimumPrivilegeLevel\":\"Administrator\",\"Password\":\"$SF_ADMIN_PASSWORD\"}}")

TOKEN=$(echo "$RESPONSE" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d['data']['authenticationToken'])" 2>/dev/null || true)

if [ -z "$TOKEN" ]; then
  echo "$(date -u): ERROR: PasswordLogin failed: $RESPONSE"
  exit 1
fi

# ---- Trigger server save ----
echo "$(date -u): Triggering server save..."
curl -sk -X POST "$SERVER/api/v1" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"function":"SaveGame","data":{"SaveName":"backup"}}' > /dev/null
sleep 5

# ---- Write rclone config ----
cat > "$RCLONE_CONF" << CONF
[r2]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY_ID
secret_access_key = $R2_SECRET_ACCESS_KEY
endpoint = https://$R2_ACCOUNT_ID.$${R2_JURISDICTION:+$R2_JURISDICTION.}r2.cloudflarestorage.com
no_check_bucket = true
CONF
chmod 600 "$RCLONE_CONF"

# ---- Upload ----
TIMESTAMP=$(date -u +"%Y-%m-%dT%H-%M")
echo "$(date -u): Uploading to r2:$R2_BUCKET_NAME/$TIMESTAMP/ ..."
rclone copy "$SAVES_DIR" "r2:$R2_BUCKET_NAME/$TIMESTAMP/" --config "$RCLONE_CONF"

# ---- Prune: delete all but the newest KEEP backups ----
echo "$(date -u): Pruning old backups (keeping $KEEP)..."
rclone lsd "r2:$R2_BUCKET_NAME/" --config "$RCLONE_CONF" \
  | awk '{print $NF}' | sort \
  | head -n -$KEEP \
  | while read -r dir; do
      echo "$(date -u): Deleting old backup: $dir"
      rclone purge "r2:$R2_BUCKET_NAME/$dir" --config "$RCLONE_CONF"
    done

echo "$(date -u): Backup complete."
SCRIPT
chmod +x /usr/local/bin/satisfactory-backup.sh

# ---------------------------------------------------------------------------
# systemd — one-shot claim service
# ---------------------------------------------------------------------------
cat > /etc/systemd/system/satisfactory-claim.service << 'EOF'
[Unit]
Description=Claim Satisfactory Dedicated Server
After=satisfactory.service
Requires=satisfactory.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/satisfactory-claim.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal
SyslogIdentifier=satisfactory-claim

[Install]
WantedBy=multi-user.target
EOF

# ---------------------------------------------------------------------------
# systemd — hourly backup timer
# ---------------------------------------------------------------------------
cat > /etc/systemd/system/satisfactory-backup.service << 'EOF'
[Unit]
Description=Satisfactory Server Backup to Cloudflare R2
After=satisfactory.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/satisfactory-backup.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=satisfactory-backup
EOF

cat > /etc/systemd/system/satisfactory-backup.timer << 'EOF'
[Unit]
Description=Hourly Satisfactory Server Backup

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable satisfactory-claim.service
systemctl enable satisfactory-backup.timer
systemctl start --no-block satisfactory-claim.service
systemctl start satisfactory-backup.timer

echo "=== Bootstrap complete. Satisfactory server is starting. ==="
echo "Monitor with: journalctl -u satisfactory -f"
