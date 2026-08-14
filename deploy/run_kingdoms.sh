#!/usr/bin/env bash
# ============================================================
# run_kingdoms.sh — Démarre TOUTES les royautés de The Last Clan
# en parallèle sur le VPS (modèle « royaumes/saisons »).
#
# Chaque royaume écoute sur SON port avec SA room => son propre
# monde déterministe (= sa saison). Résumé des royaumes :
#   Royaume Alpha : ENet  TCP/UDP 7934  room royaume-alpha  (PC)
#   Royaume Beta  : ENet  TCP/UDP 7935  room royaume-beta   (PC)
#   Royaume Web   : WSS   TCP    7938  room royaume-web    (navigateur/mobile)
#
# Usage :  ./run_kingdoms.sh
# Nécessite : godot headless dans le PATH (ou GODOT_BIN), certificats TLS.
# ============================================================
set -u

GODOT_BIN="${GODOT_BIN:-/usr/local/bin/godot}"
PROJECT="/opt/the-last-clan"
LOG_DIR="/var/log/the-last-clan"
mkdir -p "$LOG_DIR"

TLS_CERT="${TLS_CERT:-/etc/letsencrypt/live/lastclan.imaginbox.fr/fullchain.pem}"
TLS_KEY="${TLS_KEY:-/etc/letsencrypt/live/lastclan.imaginbox.fr/privkey.pem}"

# Vérifie que le binaire Godot existe.
if [ ! -x "$GODOT_BIN" ]; then
  echo "ERREUR : binaire Godot introuvable : $GODOT_BIN"
  exit 1
fi

# Vérifie que les certificats TLS existent (requis pour le royaume Web wss).
if [ ! -f "$TLS_CERT" ] || [ ! -f "$TLS_KEY" ]; then
  echo "AVERTISSEMENT : certificats TLS introuvables ($TLS_CERT / $TLS_KEY)."
  echo "Le Royaume Web (wss) ne démarrera PAS. Configurez Let's Encrypt, puis relancez."
fi

echo "Démarrage des royaltaés de The Last Clan sur $PROJECT ..."

# --- Royaume Alpha (ENet, PC, Saison 1) — port 7934 -------------------------
nohup "$GODOT_BIN" --headless --path "$PROJECT" \
  -- --host --port=7934 --room=royaume-alpha --autostart \
  > "$LOG_DIR/royaume-alpha.log" 2>&1 &
echo "  [ok] Royaume Alpha  : ENet  7934  (log: $LOG_DIR/royaume-alpha.log)"

# --- Royaume Beta (ENet, PC, Saison 2) — port 7935 --------------------------
nohup "$GODOT_BIN" --headless --path "$PROJECT" \
  -- --host --port=7935 --room=royaume-beta --autostart \
  > "$LOG_DIR/royaume-beta.log" 2>&1 &
echo "  [ok] Royaume Beta   : ENet  7935  (log: $LOG_DIR/royaume-beta.log)"

# --- Royaume Web (WebSocket sécurisé wss, navigateur/mobile) — port 7938 ----
if [ -f "$TLS_CERT" ] && [ -f "$TLS_KEY" ]; then
  nohup "$GODOT_BIN" --headless --path "$PROJECT" \
    -- --ws-host --port=7938 --room=royaume-web \
    --tls-cert="$TLS_CERT" --tls-key="$TLS_KEY" \
    > "$LOG_DIR/royaume-web.log" 2>&1 &
  echo "  [ok] Royaume Web   : WSS   7938  (log: $LOG_DIR/royaume-web.log)"
else
  echo "  [--] Royaume Web ignoré (TLS manquant)."
fi

echo
echo "Toutes les royautés lancées. Journaux : $LOG_DIR"
echo "Pour ajouter un royaume : dupliquez un bloc ci-dessus avec un nouveau"
echo "port + room, puis ajoutez-le dans res://servers.json du jeu."
