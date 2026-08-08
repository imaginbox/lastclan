# The Last Clan — 3D

Jeu de stratégie en temps réel (RTS) 3D multijoueur, développé avec **Godot 4.7**.

## 🎮 Jouer en ligne

Le jeu est jouable directement dans le navigateur :

👉 **https://imaginbox.github.io/lastclan/**

1. Entrez votre **nom**
2. Onglet **« Créer une partie »** pour héberger, ou **« Rejoindre une partie »** avec un code
3. Partagez l'**invitation** (code) à vos amis pour qu'ils rejoignent la même partie
4. **Lancer le jeu**

## ✨ Fonctionnalités

- **RTS multijoueur** via relais WebSocket (cohabitation libre, chaque joueur a sa base)
- **Ressources** : Or, Bois, Pierre — les modèles shrinks à mesure qu'ils s'épuisent
- **Villageois** qui récoltent automatiquement
- **Bâtiments** : Maison, Ferme, etc. (placeholders modélisés)
- **Chat** entre joueurs
- **Web** (HTML5) et **Desktop** (Windows)

## 🏗️ Développement

- **Godot 4.7** (rendu Web/Compatibility)
- Scripts : `scripts/`
- Scènes : `scenes/`
- Modèles 3D : `assets/models/`

## 🚀 Déploiement automatique

Le workflow GitHub Actions (`.github/workflows/deploy.yml`) exporte le jeu en Web
et le publie automatiquement sur **GitHub Pages** à chaque `push` sur `main`.

## 🖥️ Jouer en local (Desktop)

Lancez le projet dans Godot 4.7 (`project.godot`) et appuyez sur **F5**.

Test multijoueur local : dans le menu, bouton **« Lancer un 2e joueur (test local) »**.

---
Jeu fait avec ❤️ et Godot.
