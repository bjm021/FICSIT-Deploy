#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/satisfactory-setup.log) 2>&1

echo "=== Satisfactory Dedicated Server bootstrap ==="

# ---------------------------------------------------------------------------
# System setup
# ---------------------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  lib32gcc-s1 \
  curl \
  wget \
  unzip \
  htop \
  screen

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

echo "=== Bootstrap complete. Satisfactory server is starting. ==="
echo "Monitor with: journalctl -u satisfactory -f"
