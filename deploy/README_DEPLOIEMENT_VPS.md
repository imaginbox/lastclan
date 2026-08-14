# Déployer un serveur The Last Clan 24/24 sur Hostinger VPS (sans Ziva)

Ce guide permet de faire tourner un **vrai serveur de jeu dédié** sur ton VPS
Hostinger, hébergé par ton propre Godot, **sans aucune dépendance à Ziva ni à un
abonnement**. Les joueurs se connectent directement à l'IP:port de ton VPS.

## Comment ça marche (architecture)

```
 Ton VPS Hostinger (Linux, root)        Tes joueurs (PC/Android/Web)
┌────────────────────────────────┐      ┌──────────────────────────────┐
│ Godot --headless -- --host     │◄ENet►│ Client Godot -- --connect=IP │
│   écoute sur le port 7934      │      │   (IP publique du VPS)       │
│   = serveur de jeu dédié       │      └──────────────────────────────┘
└────────────────────────────────┘
```

- Le serveur est **peer 1** (le vrai hôte, plus un fantôme comme avec Ziva).
- Chaque client se connecte et reçoit la même **graine de monde** (déterministe)
  → monde identique pour tous.
- Tout passe en **peer to peer direct** via ENet (UDP) — aucun relais central.
- `systemd` garde le serveur actif 24/24 et le relance automatiquement si crash.

---

## Étape 1 — Créer ton VPS

Chez Hostinger, prends un **VPS KVM 1** (1 vCPU, 1 GB RAM, utlise la distribution
**Ubuntu 22.04** ou **Debian 12**). Active l'accès root + SSH (Hostinger fournit
l'IP et le mot de passe root, ou une clé SSH).

## Étape 2 — Se connecter au VPS

Depuis ton PC (Terminal/Windows PowerShell avec `ssh`) :

```bash
ssh root@IP_DU_VPS
```

## Étape 3 — Installer Godot (headless) sur le VPS

```bash
# Mise à jour du système
apt update && apt upgrade -y

# Dépendances pour Godot headless
apt install -y unzip wget libx11-6 libxcursor1 libxrandr2 \
  libxinerama1 libxi6 libgl1 libegl1 libpulse0 libglib2.0-0

# Télécharge Godot 4.7.1 LINUX (version headless/server)
cd /opt
wget https://github.com/godotengine/godot/releases/download/4.7.1-stable/\
Godot_v4.7.1-stable_linux.x86_64.zip
unzip Godot_v4.7.1-stable_linux.x86_64.zip
chmod +x Godot_v4.7.1-stable_linux.x86_64
mv Godot_v4.7.1-stable_linux.x86_64 /usr/local/bin/godot
```

Vérifie : `godot --version`

## Étape 4 — Mettre le jeu sur le VPS

Depuis ton PC, génère un **export pour serveur** (PCK) du jeu et envoie-le avec
`scp` :

```bash
# Sur ton PC : exporter le projet en "Linux Dedicated Server" depuis l'éditeur
# Godot (Export → nouveau preset Linux → cocher "Export as dedicated server"),
# et récupère le .pck produit.

# Ensuite, depuis ton PC :
scp -r /chemin/vers/the-last-clan-3d root@IP_DU_VPS:/opt/the-last-clan
```

> Alternative simple pendant le développement : copier TOUT le dossier du projet
> avec `scp`, puis utiliser `godot --path /opt/the-last-clan -- --host`.
> (Plus lourd mais fonctionne sans exporter.)

## Étape 5 — Ouvrir le port

Le serveur écoute en **UDP** (ENet) sur le port **7934** par défaut. Ouvre-le :

```bash
# Autorise le port dans le firewall (si ufw est actif)
ufw allow 7934/udp
ufw allow 7934/tcp   # (au cas où)
ufw status
```

> Ajoute aussi une **règle de pare-feu dans le panneau Hostinger** (Network →
> Firewall) ouvrant le port 7934 UDP.

## Étape 6 — Démarrer le serveur en avant-plan (test rapide)

```bash
cd /opt/the-last-clan
godot --headless --path . -- --host --port=7934
```

Tu devrais voir : `Serveur démarré sur le port 7934`. Ctrl+C pour arrêter.

## Étape 7 — Service systemd (24/24 avec redémarrage auto)

Copie le fichier `the-last-clan.service` fourni (voir ce dossier) dans systemd :

```bash
cp /opt/the-last-clan/deploy/the-last-clan.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable the-last-clan
systemctl start the-last-clan
systemctl status the-last-clan   # vérifie que c'est "active (running)"
```

Commandes utiles :
```bash
systemctl status the-last-clan     # état
journalctl -u the-last-clan -f     # logs en direct
systemctl restart the-last-clan    # redémarrer
```

`systemd` relance automatiquement le serveur en cas de crash (option
`Restart=always`).

## Étape 8 — Les joueurs se connectent

Sur le jeu (depuis le lobby), chaque joueur rejoint ton serveur avec l'adresse
`IP_DU_VPS:7934` :

- **En ligne de commande** : `Godot --path . -- --connect=IP_DU_VPS:7934 --name=Joueur`
- **Via le lobby** : (ajouter un champ IP dans l'UI est prévu — voir FAQ)

---

## ⭐ Multi-royautés : plusieurs serveurs/saisons en parallèle (style Call of Dragons)

Tu peux faire tourner **plusieurs « royaumes » (saisons)** sur le même VPS, chacun
avec sa propre room → sa propre graine de monde → un monde/saison différent.
Le lobby affiche une liste : « Choisir un serveur (royaume) ». Le joueur clique
sur un royaume et le rejoint.

### Les royaumes préconfigurés

| Royaume      | Transport | Port | Room            | Cible           |
|--------------|-----------|------|-----------------|-----------------|
| ⭐ Royaume Alpha | ENet (UDP) | 7934 | royaume-alpha   | PC (bureau)     |
| ⭐ Royaume Beta  | ENet (UDP) | 7935 | royaume-beta    | PC (bureau)     |
| 🌐 Royaume Web   | WSS (TCP)  | 7938 | royaume-web     | navig. / mobile |

### Ouvrir les ports

```bash
ufw allow 7934/udp && ufw allow 7934/tcp
ufw allow 7935/udp && ufw allow 7935/tcp
ufw allow 7938/tcp          # WebSocket sécurisé (wss)
ufw status
```
(Ouvre aussi 7934/7935/7938 dans le **pare-feu du panneau Hostinger**.)

### Lancer tous les royaumes d'un coup

Le script `deploy/run_kingdoms.sh` démarre les trois royaumes en parallèle.
Installe-le comme service systemd unique (24/24 + redémarrage auto) :

```bash
cp /opt/the-last-clan/deploy/the-last-clan-kingdoms.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable the-last-clan-kingdoms
systemctl start the-last-clan-kingdoms
systemctl status the-last-clan-kingdoms
journalctl -u the-last-clan-kingdoms -f
```

Chaque royaume écrit son propre log dans `/var/log/the-last-clan/` :
`royaume-alpha.log`, `royaume-beta.log`, `royaume-web.log`.

### Le royaume Web (wss) nécessite un domaine + certificat TLS

Le Royaume Web sert les navigateurs (itch.io). Une page HTTPS bloque `ws://`, il
faut donc `wss://` avec un certificat. Configure ton domaine (ex. `lastclan.imaginbox.fr`)
avec Let's Encrypt, puis `run_kingdoms.sh` utilisera automatiquement les certificats
(voir `README_ITCHIO.md`).

### Ajouter un nouveau royaume (ex. Royaume Gamma, Saison 3)

1. **Côté serveur** : duplique un bloc dans `run_kingdoms.sh` avec un nouveau port
   + room (ex. `--port=7936 --room=royaume-gamma`).
2. **Côté jeu** : ajoute l'entrée dans `res://servers.json` (name, transport,
   address, room). Puis re-exporte (`build_web.bat` pour la version web).
3. Relance le service : `systemctl restart the-last-clan-kingdoms`.

### Comment le monde est-il cohérent entre royaumes ?

Le serveur de chaque royaume transmet son `room_id` au client à la connexion via
`_sync_room` (RPC). Le client recalcule sa graine de monde depuis ce `room_id` :
ainsi **tous les joueurs d'un même royaume voient le même monde**, et chaque
royaume a un monde différent (saison différente).

---

## FAQ

### Comment je lance un serveur local pour tester sans VPS ?
```bash
# Terminal A
godot --path . -- --host --port=7934
# Terminal B (2e client)
godot --path . -- --connect=127.0.0.1:7934 --name=Joueur2
```

### Le port change-t-il ?
Ajoute `--port=XXXX` au serveur et au client : `--connect=IP:XXXX`.

### Combien de joueurs ?
16 clients max par défaut (`MAX_CLIENTS`). Modifiable dans `Lobby.gd`.

### C'est sécurisé ?
Le serveur direct est plus simple que le relais : pas de métrage/de quota, et
c'est toi qui contrôles l'IP. (Pas d'auth par défaut : seul le code de partie /
le nom sépare les joueurs, comme dans beaucoup de RTS amicaux.)

### Je veux un code de partie effectif sur le serveur ?
Pour l'instant une seule partie vit sur le serveur. Pour du multi-parties, on
peut router par `net_port` (un port = une partie) ou introduire un code vérifié
par le serveur. Demande-moi si tu veux ça.
