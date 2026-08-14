#!/usr/bin/env bash
# The Last Clan — lanceur rapide du serveur dédié (auto-hébergé, sans Ziva).
# Usage :
#   ./run_server.sh                 -> port par défaut 7934
#   ./run_server.sh 9000            -> port 9000
set -euo pipefail

PORT="${1:-7934}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Lancement du serveur The Last Clan sur le port ${PORT} (UDP/ENet)..."
echo "    Chemin projet : ${PROJECT_DIR}"
echo "    Les joueurs se connectent via : --connect=IP_DU_VPS:${PORT}"

exec godot --headless --path "${PROJECT_DIR}" -- --host --port="${PORT}"
