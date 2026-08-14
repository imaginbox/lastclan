# 🇫🇷 DÉPLOIEMENT VPS AUTO-HÉBERGÉ (sans Ziva, sans Cloudflare)

Ce kit fait tourner **The Last Clan** sur ton propre VPS (OVH / Hetzner / DigitalOcean…).
Le serveur est un **vrai serveur WebSocket Godot** (peer 1) qui accueille directement
les joueurs : plus aucun relais Ziva, plus aucune dépendance aux IP Cloudflare.
Ton FAI n'a plus à joindre le relais → **le routage instable n'existe plus**.

> Pourquoi ça contourne ton problème : le blocage de Telecom Algeria touchait
> uniquement certaines IP **Cloudflare**. Un VPS chez OVH/Hetzner est derrière un
> autre réseau (datacenters européens, bien interconnectés avec l'Algérie). Les
> joueurs se connectent à *ton* IP/domaine, pas à Cloudflare.

---

## 1. Ce qu'il te faut

| Élément | Détail |
|---------|--------|
| **VPS** | Linux (Debian/Ubuntu), min. 2 vCPU / 4 Go RAM, IP publique. ~3-6 €/mois |
| **Domaine (recommandé)** | ex. `lastclan.imaginbox.fr` pointant (A record) vers l'IP du VPS — nécessaire pour le certificat TLS gratuit et un `wss://mondomaine` propre |
| **Certificat TLS** | Gratuit via **Certbot (Let's Encrypt)** — obligatoire pour les navigateurs (contenu mixte bloqué sinon) |
| **Godot server** | Binaire Linux `Godot_v4.7.1-stable_linux.x86_64` (ou l'import/export "Linux Server") |

> Sans domaine : impossible d'avoir `wss://` valide pour les navigateurs (les browsers
> bloquent le contenu mixte). Tu peux tester avec un domaine gratuit (duckdns) ou un
> sous-domaine, mais il **faut** un domaine + cert TLS pour le web.

---

## 2. Script d'installation (à lancer sur le VPS, en root)

`setup_server.sh` installe tout : Godot, Certbot, le pare-feu, et copie le service.

```bash
# Sur le VPS :
sudo bash setup_server.sh lastclan.imaginbox.fr
```

**Ce que fait le script :**
1. Installe Godot 4.7.1 Linux (binaire serveur)
2. Récupère un certificat TLS via Certbot pour ton domaine (auto-renouvellement)
3. Ouvre le port **7934** dans le pare-feu (ufw)
4. Dépose l'unité systemd `lastclan-server.service` + l'active

---

## 3. Le jeu (code & scènes) sur le VPS

Le serveur tourne depuis **ce dépôt Git** directement (mode `--ws-host`). Sur le VPS :

```bash
git clone https://github.com/imaginbox/lastclan.git /srv/lastclan
cd /srv/lastclan
```

Le serveur est lancé par systemd avec :
```
Godot_v4.7.1 --headless --path /srv/lastclan -- --ws-host \
   --port=7934 --room=royaume-web \
   --tls-cert=/etc/letsencrypt/live/lastclan.imaginbox.fr/fullchain.pem \
   --tls-key=/etc/letsencrypt/live/lastclan.imaginbox.fr/privkey.pem
```

> `--ws-host` : le lobby autoload `Lobby.gd` détecte ce flag, démarre un vrai serveur
> WebSocket sécurisé (`wss://`) qui écoute, et auto-lance `Main.tscn` (peer 1).

---

## 4. Configuration des royaumes (côté joueur)

Dans `res://servers.json`, le royaume pointe vers ton VPS :

```json
{
  "name": "Royaume Web",
  "subtitle": "Serveur officiel (VPS)",
  "transport": "ws",
  "address": "wss://lastclan.imaginbox.fr:7934",
  "room": "royaume-web",
  "official": true
}
```

Le lobby (`LobbyMenu._on_server_pressed`) détecte `transport == "ws"` et appelle
`Lobby.join_server("ws", address, room)` → connexion directe à ton serveur.

---

## 5. Service systemd (démarrage auto 24/7)

L'unité `lastclan-server.service` garantit :
- démarrage au boot du VPS
- redémarrage automatique en cas de crash (`Restart=always`)
- logs dans `journalctl -u lastclan-server`

```bash
sudo systemctl enable lastclan-server
sudo systemctl start lastclan-server
sudo journalctl -u lastclan-server -f   # voir les logs
```

---

## 6. Vérification

Depuis ta machine (et depuis le navigateur déployé) :
```bash
# TCP + TLS ouverts ?
curl -sS -o /dev/null -w "%{http_code}\n" "https://lastclan.imaginbox.fr:7934"
# → une réponse TLS/HTTP (même code d'erreur) prouve que le port est ouvert et joignable

# Test manuel du serveur localement (depuis le VPS, sans TLS) :
Godot_v4.7.1 --headless --path /srv/lastclan -- --ws-host --port=7934 --room=royaume-web
```

---

## 7. Limites & honnêteté

- **Nécessite un VPS allumé 24/7** (~3-6 €/mois) + un domaine. C'est le coût réel de
  l'indépendance vis-à-vis du relais.
- **Écrit en lecture seule côté mobil** : tout tourne sur ton serveur comme avant
  (synchronisation owner-authoritative, monde déterministe par `room_id`).
- Le code client **supportait déjà** tout ça (`_host_server`/`join_server`) : c'est
  pour ça que `--ws-host` et `--tls-*` existaient déjà dans `Lobby.gd`.
- **Backup** : pense à sauvegarder le dépôt et les données serveur (`user://`).

---

Fichiers du kit : `setup_server.sh`, `run_server.sh`, `lastclan-server.service`.
