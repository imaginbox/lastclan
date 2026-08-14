#!/usr/bin/env bash
# =============================================================================
#  setup_server.sh — Installe The Last Clan (serveur WebSocket VPS) sur Linux.
#
#  Usage (en root) :  sudo bash setup_server.sh <DOMAINE>
#  Exemple         :  sudo bash setup_server.sh lastclan.ovh
#
#  Ce qui est fait :
#   1. apt update/upgrade + paquets de base (git, curl)
#   2. Télécharge le binaire serveur Godot 4.7.1 Linux  (x86_64)
#   3. Installe Certbot + récupère un certificat TLS pour <DOMAINE>
#   4. Ouvre le port 7934 dans le pare-feu ufw
#   5. Dépose + active l'unité systemd lastclan-server.service
#
#  NOTE : le dépôt du jeu est supposé cloné dans /srv/lastclan.
#         (git clone https://github.com/imaginbox/lastclan.git /srv/lastclan)
# =============================================================================
set -euo pipefail

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "❌ Usage : sudo bash setup_server.sh <DOMAINE>   (ex: lastclan.ovh)"
  exit 1
fi

PORT="7934"
GODOT_VER="4.7.1-stable"
GODOT_BIN_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VER}/Godot_v${GODOT_VER}_linux.x86_64.zip"
INSTALL_DIR="/opt/godot"
GAME_DIR="/srv/lastclan"
SERVICE_FILE="/etc/systemd/system/lastclan-server.service"

echo "=== [1/5] Mise à jour du système et paquets de base ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq git curl unzip certbot python3-certbot-nginx ufw >/dev/null

echo "=== [2/5] Installation du binaire Godot $GODOT_VER ==="
mkdir -p "$INSTALL_DIR"
if [ ! -f "$INSTALL_DIR/Godot_v${GODOT_VER}_linux.x86_64" ]; then
  echo "   Téléchargement depuis GitHub…"
  curl -fSL -o /tmp/godot.zip "$GODOT_BIN_URL"
  unzip -o -q /tmp/godot.zip -d "$INSTALL_DIR"
  rm -f /tmp/godot.zip
  chmod +x "$INSTALL_DIR"/Godot_v${GODOT_VER}_linux.x86_64
fi
echo "   Godot présent : $(ls "$INSTALL_DIR"/Godot_v${GODOT_VER}_linux.x86_64)"

echo "=== [3/5] Certificat TLS (Let's Encrypt) pour $DOMAIN ==="
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos \
  --register-unsafely-without-email --keep-until-expiring || \
  echo "   ⚠️ Certbot a échoué — vérifie que le DNS A pointe bien vers ce VPS et que le port 80 est libre."

CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

echo "=== [4/5] Pare-feu : ouverture du port $PORT (TCP) ==="
ufw allow "$PORT/tcp" >/dev/null || true
ufw allow 80/tcp >/dev/null || true   # pour le renouvellement certbot
ufw allow 443/tcp >/dev/null || true  # pour le renouvellement certbot
ufw --force enable >/dev/null || true

echo "=== [5/5] Déploiement de l'unité systemd ==="
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=The Last Clan — serveur WebSocket multijoueur (VPS)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$GAME_DIR
ExecStart=$INSTALL_DIR/Godot_v${GODOT_VER}_linux.x86_64 --headless --path $GAME_DIR -- --ws-host --port=$PORT --room=royaume-web --tls-cert=$CERT --tls-key=$KEY
Restart=always
RestartSec=3
Environment=HOME=/root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable lastclan-server >/dev/null 2>&1 || true

echo ""
echo "✅ Installation terminée."
echo "   ➜ Démarre le serveur :   sudo systemctl start lastclan-server"
echo "   ➜ Voir les logs      :   sudo journalctl -u lastclan-server -f"
echo "   ➜ Test               :   curl -sS -o /dev/null -w '%{http_code}\\n' https://$DOMAIN:$PORT"
echo ""
echo "   N'oublie pas de mettre à jour res://servers.json côté jeu :"
echo "     {\"name\":\"Royaume Web\",\"transport\":\"ws\",\"address\":\"wss://$DOMAIN:$PORT\",\"room\":\"royaume-web\"}"
