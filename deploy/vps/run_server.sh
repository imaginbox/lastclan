#!/usr/bin/env bash
# =============================================================================
#  run_server.sh — Lance manuellement le serveur The Last Clan (sans systemd).
#
#  Usage :  sudo bash run_server.sh <DOMAINE> [PORT]
#  Exemple: sudo bash run_server.sh lastclan.imaginbox.fr 7934
#
#  Sert au débogage avant d'activer le service systemd. Nécessite :
#    - /srv/lastclan        (dépôt Git cloné)
#    - /opt/godot/Godot_v4.7.1-stable_linux.x86_64
#    - certbot certifié pour <DOMAINE>
# =============================================================================
set -euo pipefail

DOMAIN="${1:-}"
PORT="${2:-7934}"
if [ -z "$DOMAIN" ]; then
  echo "❌ Usage : sudo bash run_server.sh <DOMAINE> [PORT]"
  exit 1
fi

GODOT="/opt/godot/Godot_v4.7.1-stable_linux.x86_64"
GAME_DIR="/srv/lastclan"
CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [ ! -f "$GODOT" ]; then echo "❌ Godot absent : $GODOT"; exit 1; fi
if [ ! -d "$GAME_DIR" ]; then echo "❌ Jeu absent : $GAME_DIR"; exit 1; fi
if [ ! -f "$CERT" ]; then echo "❌ Certificat absent : $CERT"; exit 1; fi

echo "Démarrage du serveur wss://$DOMAIN:$PORT (auro-hébergé, sans Ziva)…"
exec "$GODOT" --headless --path "$GAME_DIR" -- \
  --ws-host \
  --port="$PORT" \
  --room=royaume-web \
  --tls-cert="$CERT" \
  --tls-key="$KEY"
