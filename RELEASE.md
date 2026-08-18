# 📦 Guide de publication — The Last Clan

Deux livrables : une **version Web** (itch.io) et une **version Windows .exe**
(avec **mise à jour automatique** intégrée).

---

## 1. Construire les builds

Depuis la racine du projet (Windows) :

```bat
:: Web (itch.io) — produit build/web/ + zip itch.io
build_web.bat

:: Windows .exe (auto-update) — produit build/win/ + zip Windows
```

Les `.zip` prêts à uploader sont dans `build/` :
- `build/TheLastClan_itchio.zip`  → **Web** (à uploader sur itch.io)
- `build/TheLastClan_Windows.zip` → **Windows** (.exe + .pck, auto-update)

---

## 2. Publier une nouvelle version (pour l'auto-updater)

Le .exe se met à jour tout seul en lisant les **GitHub Releases**. Pour sortir
une version :

1. **Incrémenter la version locale**
   dans `scripts/UpdateManager.gd` :
   ```gdscript
   const APP_VERSION := "1.1.0"
   ```
2. **Reconstruire** le build Windows (`build/TheLastClan_Windows.zip`).
3. **Créer une GitHub Release** :
   - tag : `v1.1.0` (doit correspondre à APP_VERSION, sans le `v`)
   - titre : `v1.1.0`
   - notes : résumé des nouveautés (affichées au joueur)
   - **joindre le fichier** `TheLastClan_Windows.zip` comme asset
4. Fait. Les joueurs qui lancent l'ancien .exe verront le panneau
   « Mise à jour disponible » et pourront se mettre à jour en un clic.

> ⚠️ Le tag doit être strictement supérieur à l'APP_VERSION embarqué.
> La comparaison est numérique (`1.10.0` > `1.9.9`), le préfixe `v` est ignoré.

---

## 3. Publier sur itch.io (version Web)

1. **itch.io → Upload new project** → Type : **HTML**
2. Déposer `build/TheLastClan_itchio.zip`
3. Optionnel : cocher **Mobile friendly**, Viewport **Full**
4. Pour mettre à jour la page : re-téléverser le nouveau `.zip` (la version Web
   se met à jour au rechargement de la page, pas besoin d'auto-updater).

---

## 4. Déploiement en ligne (GitHub Pages)

`git push` sur `main` → GitHub Actions exporte le Web et publie sur
**https://imaginbox.github.io/lastclan/** automatiquement.

---

## Remarques

- Le **Web** ne gère pas l'auto-update (impossible d'écrire dans le navigateur) :
  la version se met à jour simplement en rechargeant la page / re-téléversant le zip.
- L'**auto-update Windows** écrit dans le dossier du jeu : si le jeu est dans un
  dossier protégé (ex. `Program Files`), il faut le déplacer dans un dossier
  accessible (ex. `C:\Jeux\`).
