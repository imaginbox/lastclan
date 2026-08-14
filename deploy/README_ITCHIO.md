# Publier The Last Clan sur itch.io (navigateur + mobile) — multi avec self-hosted WebSocket

Ce guide complète `README_DEPLOIEMENT_VPS.md`. Il explique comment :
1. Mettre ton jeu sur **itch.io** (jouable dans le navigateur et sur mobile web).
2. Faire fonctionner le **multijoueur** : le client (navigateur) se connecte à
   **ton serveur WebSocket** sur ton VPS — **toujours sans Ziva**.

> ⚠️ Le jeu supporte maintenant DEUX transports (voir `Lobby.gd`) :
> - **ENet (UDP)** → jeu de bureau installé (desktop). `--host` / `--connect=IP:PORT`
> - **WebSocket** → navigateur / itch.io / mobile web. `--ws-host` / `--ws-connect=URL`
>
> Pour itch.io, on utilise le **WebSocket**.

---

## Rappel : pourquoi WebSocket et pas ENet ?

Les navigateurs ne permettent pas d'envoyer de l'UDP brut. Une build WebGL (celle
d'itch.io) ne peut communiquer en multijoueur que par **WebSocket** (`ws://`/`wss://`).
C'est pour ça qu'on utilise le transport WebSocket pour la version web.

## Le point délicat : TLS / wss:// obligatoire

itch.io sert ton jeu en **HTTPS**. Un navigateur sur une page HTTPS **bloque** les
connexions WebSocket non sécurisées (`ws://`) vers une adresse distante (contenu
mixte). Donc :
- ❌ `ws://ton-vps:7938` → **bloqué** par le navigateur.
- ✅ `wss://mondomaine.fr:7938` → fonctionne (WebSocket sécurisé TLS).

Il te faut donc un **nom de domaine (ou sous-domaine)** pointant vers ton VPS,
avec un **certificat TLS** (gratuit via Let's Encrypt / Certbot), et lancer ton
serveur Godot **WebSocket avec TLS**.

---

## Étape 1 — Ouvrir le port WebSocket

Ton serveur WebSocket écoute sur le port (ex. **7938**). Ouvre-le en TCP/UDP :

```bash
ufw allow 7938/tcp
ufw allow 7938/udp
```

(Pour wss://, c'est du TCP sous TLS.)

## Étape 2 — Nom de domaine + certificat TLS (Let's Encrypt)

Réserve un domaine (ex. `thelastclan.example.com`) chez un registrar et ajoute un
enregistrement **A** pointant vers l'IP de ton VPS. Puis installe Certbot et
génère un certificat :

```bash
apt install -y certbot
certbot certonly --standalone -d thelastclan.example.com
# créé : /etc/letsencrypt/live/thelastclan.example.com/{fullchain.pem, privkey.pem}
```

> Configurer un reverse-proxy (nginx/caddy) devant Godot pour le wss est possible
> mais Godot sait faire le TLS lui-même si on lui donne le certificat. Voir Étape 3.

## Étape 3 — Lancer le serveur WebSocket TLS sur le VPS

Copie le certificat quelque part de stable, puis lance Godot en mode WebSocket avec
TLS. Exemple de service systemd :

```ini
[Unit]
Description=The Last Clan WebSocket Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/the-last-clan
ExecStart=/usr/local/bin/godot --headless --path /opt/the-last-clan \
  -- --ws-host --port=7938 \
  --tls-cert=/etc/letsencrypt/live/thelastclan.example.com/fullchain.pem \
  --tls-key=/etc/letsencrypt/live/thelastclan.example.com/privkey.pem
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Puis :

```bash
cp the.last.clan.ws.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now the.last.clan.ws
journalctl -u the.last.clan.ws -f
```

Ton serveur écoute alors en **`wss://thelastclan.example.com:7938`**.

> 💡 Le port. On met le wss sur un port non standard (7938). C'est simple et
> fonctionnel. (Un reverse-proxy nginx sur le 443 gérerait le TLS proprement,
> mais Godot fait déjà le TLS ici — plus simple.)

## Étape 4 — Pointer le client web vers ton serveur wss

Actuellement le client Web se connecte via la ligne de commande :
`--ws-connect=wss://thelastclan.example.com:7938`.

Pour une version jouable sans ligne de commande (recommandé pour itch.io), il faut
un **champ IP/adresse dans le lobby**. Deux options :
- **Option A (recommandée)** : je t'ajoute un champ dans l'UI du lobby où le joueur
  tape l'adresse du serveur WebSocket avant de rejoindre. (Demande-moi et je le fais.)
- **Option B** : une constante par défaut dans le code pointant vers ton serveur,
  pour que les joueurs n'aient rien à taper.

Dis-moi laquelle tu préfères.

## Étape 5 — Générer la build WebGL

On a déjà tout en place. Depuis ton PC :

```
build_web.bat
```

Cela produit `build/web/` (index.html, index.wasm, index.pck). C'est déjà testé :
**l'export WebGL compile sans erreur** (wasm ~38 Mo + pck ~90 Mo).

## Étape 6 — Publier sur itch.io

1. Va sur https://itch.io/game/new
2. Remplis le formulaire.
3. Section **Uploads** → **Upload files** → choisis le **dossier `build/web/`**
   (ou zippe-le : `zip -r the-last-clan-web.zip build/web/*`).
   Le `.zip` doit contenir `index.html` à la racine du zip (ou sélectionne le
   dossier directement avec "folder" type upload si tu as butler).
4. Type **HTML** → coche **"This file will be played in the browser"**.
5. Bouton **View page / Publish**.

La build WebGL joue alors directement dans le navigateur sur ta page itch.io,
accessible sur **PC et mobile** (rendu `gl_compatibility`, tactile activé).

## Étape 7 — Tester

- **En local (PC)** : lance un serveur WebSocket en avant-plan dans un terminal,
  puis un client WebSocket dans un autre :
  ```bash
  # Terminal A
  godot --path . -- --ws-host --port=7938
  # Terminal B
  godot --path . -- --ws-connect=ws://127.0.0.1:7938 --name=Joueur
  ```
- **Sur itch.io** : une fois le serveur wss déployé, le joueur ouvre ta page
  itch.io et rejoint via l'adresse wss du VPS.

---

## FAQ spécifique itch.io

### Mon jeu a des fichiers écrits dans user:// — ça marche sur le web ?
Oui. En WebGL, `user://` est stocké dans le **stockage local du navigateur**
(IndexedDB) du visiteur. Chaque joueur a son propre profil.

### Peut-on éviter d'ouvrir un port ?
Peut-on planquer le wss derrière le 443 ? Oui avec nginx `stream`/`map` (bloquer
upgrade). Mais le plus simple est le port dédié 7938. Si tu veux du 443 "propre",
demande-moi et je te fournis une config nginx.

### C'est gratuit ? / Fini l'abonnement Ziva ?
Oui. Tout est sur **ton VPS** (tu payes déjà le VPS). itch.io est gratuit pour
publier. **Plus aucun abonnement Ziva nécessaire.**

### Le multijoueur est-il aussi bon que le desktop ?
Le WebSocket est un peu plus lent/chatouilleux que l'ENet natif sur le net, mais
parfaitement utilisable pour un RTS amical. Le desktop garde l'ENet (meilleur).
