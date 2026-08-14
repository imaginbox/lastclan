# The Last Clan 3D — Game Design & Roadmap

> Document vivant. Adapté à l'architecture actuelle (monde partagé + persistant,
> seed déterministe par royaume, serveur dédié VPS, auto-deploy GitHub Actions).

---

## 1. VISION GLOBALE

Un **royaume = un serveur = un monde persistant partagé** dans lequel n'importe
quel joueur se connecte et joue. **CE SONT LES JOUEURS qui décident du sort de
leur royaume** : ils peuvent le ruiner (PvP, conflits, inactivité) ou le rendre
prospère (coopération, alliance solide, économie forte).

Le tout se déroule par **saisons** avec un cycle de vie complet :

```
  [Saison 1 : Développement]
       phases d'économie + construction d'un alliance globale
                    │ fin de saison
                    ▼
  FUSION : les joueurs restants migrent vers un serveur frais
           qui rejoint 4 autres serveurs du même niveau
                    │
                    ▼
  [Saison 2 : AFFRONTEMENT inter-serveurs (KvK)]
       chaque serveur est représenté par SON alliance
       → vraies guerres entre royaumes
```

**Modèle de référence : Call of Dragons / Last War / Rise of Kingdoms (KvK).**

---

## 2. STRUCTURE SAISONNIÈRE

| Étape | Ce qui se passe |
|---|---|
| **Saison (phase développement)** | Les joueurs construisent, récoltent, s'allient. Objectif : économie + alliance forte. |
| **Fin de saison** | Statistiques du royaume figées. Les survivants « émigrent » vers un serveur frais. |
| **Fusion (merging)** | Le serveur frais est réuni avec 4 autres serveurs de même niveau. |
| **Conflict (KvK)** | Les alliances de chaque serveur s'affrontent sur une carte de guerre partagée. |

Le serveur **réinitialise** son monde à chaque saison (nouveau seed, nouveau
royaume) — c'est cohérent avec `_compute_world_seed(room_id + saison)`.

---

## 3. SAISON 1 — CONTENU (ce qu'on construit MAINTENANT)

La Saison 1 est une **saison de développement (pre-KvK)**. Pas de guerre inter-
serveur. On pose le socle : **écosystème, interface, jouabilité, manipulation**
des personnages (l'accent demandé).

### 3.1 Le monde partagé (déjà en place ✅)
- Tous les joueurs d'un royaume partagent LE MÊME monde (décor + ressources
  identiques grâce au seed déterministe).
- Chaque joueur a sa base placée **en anneau** autour du centre.
- **Évolution :** convertir la carte en vrai **territoire partagé** où les joueurs
  peuvent occuper des emplacements de base (et plus tard des avant-postes).

### 3.2 Économie dynamique (cœur de l'écosystème)
Les joueurs **influencent l'économie du royaume** :
- **Courtier / marché** : un marché commun où les prix évoluent selon l'offre et
  la demande réelle des joueurs (vendre/acheter or, bois, pierre).
- **Richesse du royaume** : indicateur global = somme des ressources produites.
  Plus les joueurs produisent, plus le royaume est « riche » → débloque des bonus.
- **Épuisement dynamique** : si trop de villageois coupent le même bois, il se
  raréfie autour de la zone (déjà : respawn déterministe, à affiner).

### 3.3 Alliances / factions (à construire — pilier de la saison)
- **Création d'alliance** : nom, blason (couleur), description, tag.
- **Gestion des membres** : inviter, promouvoir, discriminer.
- **Chat d'alliance** (séparé du chat mondial).
- **Objectif commun de saison** : l'alliance construit une « Grandeur » commune.
- **Rôle central** : à la fin de la Saison 1, c'est **l'alliance** qui représente
  le royaume en KvK.

### 3.4 « Sort du royaume » — jauge d'état du serveur (concept signature)
Une jauge globale visible par tous traduit l'état du royaume, pilotée par
l'activité collective. C'est ce qui rend « les joueurs responsables du serveur » :

| Facteur | Fait monter | Fait descendre |
|---|---|---|
| Économie | Production/trade actif | Stagnation, gaspillage |
| Sécurité | Alliance forte, défense | PvP entre alliés, bases détruites |
| Cohésion | Membres actifs, entraide | Inactivité, départs, trahison |

Quand la jauge est haute → événements positifs (bonus de récolte, marché ouvert).
Quand elle tombe → les joueurs voient leur royaume « décliner » → incitation à agir.

### 3.5 Jouabilité & manipulation des personnages
Priorité demandée : **mobile ET PC**, manipulation fluide.
- **Déjà en place ✅** : caméra tactile (pan 2 doigts, pinch), barre d'ordres
  mobile, `_ui_scale = 1.8` sur tactile, clic gauche sélection / clic droit ordre.
- **Évolutions** :
  - Boutons tactiles **gros et espacés**, zone morte pour éviter les clics
    accidentels.
  - **Menu radial / contextual** selon la sélection (bâtiment, unité, ressource).
  - Mode « marcher/sélectionner » à une seule touche pour mobile.
  - **Inspecteur d'unité** cliquable : stats, tâches, changement de ressource.

### 3.6 Interface (écrans)
1. **Écran d'accueil (Lobby)** — déjà en place ✅ : entrer nom, choisir royaume,
   voir la liste des serveurs (Alpha/Beta/Web), chat.
2. **Écran monde** — le jeu (Main) : HUD ressource (déjà), mini-carte des royaumes
   si besoin, jauge « sort du royaume ».
3. **Écran alliance** — création/gestion/membres/chat/grandeur.
4. **Écran marché** — échanger des ressources entre joueurs (économie).
5. **Écran classement (board)** — production, armée, richesse par joueur/alliance.

---

## 4. DÉFINITION DU MVP — SAISON 1 (la « base » à livrer)

Pour rester focalisé, voici le **périmètre minimal** de la première itération :

### 🟢 MVP obligatoire (Saison 1 de base)
1. ✅ **Monde partagé persistant** (déjà fonctionnel)
2. ✅ **Économie** (déjà fonctionnelle : ressources, récolte, production)
3. 🟡 **Alliances de base** : création + membres + chat d'alliance
4. 🟡 **Jauge « sort du royaume »** : suivi global simple de l'activité
5. 🟡 **Responsabilité du joueur** : impact visible sur le royaume
6. 🟢 **Âme mobile/PC** : polishing de la manipulation (menu contextuel, inspecteur)

### 🟠 Phase 2 (avant fin de saison)
7. **Marché / économie dynamique** entre joueurs
8. **Classements** (production, armée)
9. **Cible de saison** : objectif commun d'alliance affiché

### 🔴 Phase 3 (préparation KvK)
10. **Mécanique de fusion** (fin de saison → nouveau serveur)
11. **Carte de conflit** (pour la Saison 2)
12. **IA adverse / PvE events** en attendant le KvK

> Les **sons et tours sont volontairement reportés** — cohérent avec ta demande.

---

## 5. PLAN D'IMPLÉMENTATION PRIORISÉ (ordre d'exécution)

| # | Tâche | Fichiers concernés | Priorité |
|---|---|---|---|
| 1 | Modèle de données **alliance** + RPC (créer, rejoindre, chat) | `Lobby.gd`, `main.gd`, nouveau `Alliance.gd` | Haute |
| 2 | UI **Écran Alliance** (création, membres, chat, grandeur) | `LobbyMenu.gd` / nouveau `AllianceUI.gd` | Haute |
| 3 | **Jauge « sort du royaume »** + facteurs d'activité | `main.gd`, `ResourceManager.gd` | Haute |
| 4 | **Inspecteur d'unité** + **menu contextuel** (mobile/PC) | `main.gd`, `HUD` | Haute |
| 5 | Polishing **manipulation UX** (raycast, sélection, boutons) | `main.gd`, `CameraController.gd` | Moyenne |
| 6 | **Marché** entre joueurs (économie dynamique) | `main.gd`, `ResourceManager.gd` | Moyenne |
| 7 | **Classements** + cible de saison | nouvel `LeaderboardUI.gd` | Moyenne |
| 8 | **Mécanique de fin de saison / fusion** | `Lobby.gd`, `servers.json` | Basse (post-1ère saison) |

---

## 6. PRINCIPES DE DESIGN (décisions à garder)

- **Le joueur a de l'impact** : chaque action compte pour le royaume (jauge,
  économie, réputation d'alliance).
- **Mobile-first** : grands touchables, pan tactile, interfaces lisibles.
- **Simplicité de la Saison 1** : pas de guerre inter-serveur tout de suite.
- **Le serveur reste l'autorité** dans un système P2P/relais (cohérent avec
  l'existant : serveur dédié VPS).
- **Réinitialisation par saison** : nouvel élan, nouvelle carte, nouvelle chance.

---

## 7. HORS PÉRIMÈTRE (reporté volontairement)
- Sons / musique (demande explicite de report)
- Tours qui tirent / combat avancé
- Mode battle inter-serveur (KvK) → Saison 2
- Modèles de bâtiments détaillés (placeholder actuel accepté pour la base)
