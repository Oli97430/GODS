# GODS — Un explorateur spatial contemplatif en VR

*English: [README.md](README.md)*

**GODS** est un explorateur spatial **contemplatif**, sans couture et déterministe, pour **PCVR** (et bureau), réalisé avec **Godot 4.6.2**. Au cœur, c'est de l'exploration pure — sans objectifs, sans menus qui gênent — à travers quatre échelles continues : **galaxie → système stellaire → planète (orbite) → surface de planète (à pied)**, avec une **couche de survie & craft**, un **mode combat arcade optionnel**, et une **coopération en ligne** par-dessus quand on en a envie. Tout est **généré procéduralement à partir d'un seed** : un même seed produit toujours le même univers, et ce que l'on voit depuis l'orbite est exactement ce que l'on foule au sol.

> Mets un casque, choisis une étoile, plonge vers une planète, pose-toi, fabrique une torche, va pêcher sur la côte pendant que le soleil se couche, et regarde les aurores illuminer le ciel pendant que ta ligne flotte.

---

## ✨ Fonctionnalités

### Quatre échelles sans couture
- **Galaxie** — 400 systèmes générés depuis un seed global, navigables comme un nuage de points 3D. Choisis un système par seed ou sélectionne un des 16 préréglages nommés depuis le **menu de départ** avant de plonger.
- **Système** — étoile + planètes placées procéduralement sur des orbites vivantes (une seule horloge simulée).
- **Planète (orbite)** — sphère planétaire érodée avec **relief de surface ombré, terminateur jour/nuit doux et halo atmosphérique au limbe**, océans scintillants, rivières, lacs, nuages, atmosphère, lunes & anneaux.
- **Surface** — terrain streamé par chunks, exploré à pied, avec rebasage à origine flottante pour la précision.

### Un monde vivant
- **Terrain déterministe** avec érosion (type hydraulique), **lits de rivière** creusés, **lacs** et **cascades** aux forts dénivelés — cohérent entre la vue orbitale et le sol.
- **Végétation procédurale** (arbres L-systems : conifère / feuillu / palmier / tordu), herbe, décor et faune, semés par chunk et par biome.
- **Biomes** pilotés par température × humidité (désert, savane, jungle, steppe, taïga, toundra, badlands…).
- **Archétypes de planètes** pour la variété (tempérée, aride, luxuriante, gelée, volcanique, alien).
- **Cratères & volcans** intégrés au champ d'élévation partagé.
- **Cycle jour/nuit & ciel dynamique** (nuages volumétriques, lever/coucher, **aurores** sur ~40 % des planètes la nuit).
- **Étoiles, halo galactique & lunes occultés par les nuages** — la géométrie du dôme s'estompe là où un nuage passe devant, via une marche de transmittance nuageuse par shader synchronisée avec le ciel.
- **Météo** (couverture nuageuse, pluie, orages avec éclairs déterministes) — même lieu + même heure → même météo.
- **Lunes & anneaux** cohérents aux trois échelles.
- **Faune** — tortues, oiseaux et autres créatures se promènent et réagissent à ta présence.
- **Audio procédural** — ambiances synthétisées en temps réel, pas, cris de faune, UI et météo, mixés par échelle.

### Locomotion & confort
- **Marche**, **saut**, **vol libre « Iron Man »** (armure sans gravité), et un **parapente** pour planer.
- **Vignette de confort** qui se resserre avec la vitesse (anti-nausée), **rotation par cran ou continue**, le tout réglable.
- **Panneau Options worldspace** en VR (sans enlever le casque) + un overlay plat au bureau — mêmes réglages.
- **Ordinateur de poignet** en VR (regarde ton poignet gauche) : échelle, coordonnées, temps, météo, inventaire, craft, pêche, construction et points d'intérêt proches.

### Survie & craft
Tout le craft, la construction et la pêche est **entièrement optionnel** — l'explorateur contemplatif est intact si tu l'ignores.

- **Récolte** : cueille des fruits, **abats n'importe quel arbre** (geste hache) — sauvage, ceux que tu as plantés (une fois adultes) et les **arbres géants remarquables** — mine des rochers (geste pioche) pour obtenir pierre, fer, cuivre, or et cristaux.
- **Fonte** des minerais en lingots dans l'onglet **Fonderie** de l'ordinateur de poignet.
- **Fabrication** — **36 recettes organisées en 6 catégories** :
  - *Construction* — planches, murs de pierre, toits de chaume, piliers en fer, portes en cuivre, lanternes dorées.
  - *Mobilier & Décor* — **12 modèles 3D dédiés** (table, chaise, étagère, coffre, tonneau, lit, colonne, statue, barrière, échelle, escalier, fenêtre) construits procéduralement.
  - *Blocs* — blocs cubiques bois, pierre, feuillage, fer.
  - *Nourriture* — plats cuisinés à partir des récoltes.
  - *Pêche* — **canne à pêche** (4 bois).
- **Construction** : pose les pièces avec un aperçu fantôme, accroche-toi au terrain et empile-les pour construire abris et tours.
- **Édition des constructions** : vise une pièce posée pour la supprimer (ressource remboursée) ou la prendre et la déplacer — édition non destructive.
- **Blocs cubiques façon Minecraft** (1 m³) : pose sur grille, empilage face à face.
- **Jardinage** : décompose un fruit en graine, plante-la dans le sol, et un nouvel arbre pousse avec le temps.

### Pêche
- **Fabrique une canne à pêche** (4 bois, onglet Pêche de la montre).
- **Équipe-la** depuis l'inventaire Sac en un tap — la canne apparaît dans ta main droite ; l'outil de récolte et les armes se rangent automatiquement.
- **Va sur la côte** — repère un endroit où l'eau est assez profonde au bord du rivage.
- **Lance** avec la gâchette : la ligne part en arc et le bouchon se pose. Attends la touche…
- **Ferre** à la touche en rappuyant sur la gâchette : **5 variétés** (petit / moyen / grand / rare, ou un trinquet d'algues), chacun avec sa valeur de soin. **Retour haptique** manette à la touche et à la prise.
- Les poissons soignent quand tu les manges depuis l'inventaire **Sac**.

### Inventaire enrichi (Sac)
L'onglet **Sac** affiche maintenant les objets groupés par catégorie avec des **actions contextuelles par objet** :
- **Manger** — nourriture & poissons restaurent la santé.
- **Décomposer** — fruit → graine prête à planter.
- **Planter** — pose une graine directement dans le sol.
- **Poser** — dépose une pièce de mobilier dans le monde.
- **Équiper** — les objets de type équipement (canne à pêche) vont directement en main.

### Torche à main gauche
Une **torche procédurale** est toujours attachée à ta main gauche. Active-la avec **Y (gauche)** en VR (ou **L** au bureau) pour une source de lumière instantanée la nuit — sans aucun prérequis de craft.

### Qualité graphique
- **Cascades d'ombres directionnelles** (2 splits, 120 m, fondus) — chaque arbre, rocher, créature et construction projette une ombre nette sur le terrain.
- **Perspective aérienne** — le terrain lointain se fond dans la brume atmosphérique, cohérent avec la vue orbitale.
- **Debanding par dithering** — supprime les bandes de dégradé visibles sur les dalles OLED/LCD des casques dans les ciels du crépuscule.
- **Filtrage anisotropique 16×** — les textures restent nettes à angle rasant sur le terrain et les constructions.

### Matériel
- **OpenXR** (Virtual Desktop / SteamVR / natif) avec **manettes ou suivi des mains**.
- Support du gilet **bHaptics TactSuit X40** (no-op gracieux s'il est absent).
- **Repli bureau** — fonctionne sans aucun casque.

### Combat & coopération en ligne *(opt-in)*
- **Arme rangée par défaut** — équipe une arme depuis la montre et un affrontement arcade commence ; range-la et l'explorateur contemplatif est exactement comme avant.
- **3 armes** — revolver (hitscan), **fusil à plasma** (bolts voyageurs + **vraie lunette optique VR**), **lance-grenades** (explosion de zone) — recul, son et viseur propres.
- **Vagues de drones ennemis** qui évoluent devant toi, télégraphient leurs tirs et lâchent du **loot d'amélioration** (soin / dégâts× / cadence× / surbouclier).
- **Gilet bHaptics X40** en combat (recul dans la poitrine, dégâts directionnels, signaux kill/soin/bouclier).
- **Coopération en ligne** — héberger ou rejoindre par IP (P2P direct, ENet). Même seed → même univers : vous partagez la planète, voyez vos avatars (tête + mains), affrontez les vagues et partagez le loot ensemble. Strictement opt-in ; **le solo est intact**.

---

## 🖥️ Prérequis

- **OS :** Windows 10/11 (x86-64), Direct3D 12.
- **GPU :** une carte PCVR correcte (développé/réglé sur une RTX 3090).
- **VR (optionnel) :** n'importe quel runtime OpenXR — **Virtual Desktop (VirtualDesktopXR)**, **SteamVR**, ou natif — + un casque connecté. Sans casque, le jeu démarre au bureau automatiquement.
- **Haptique (optionnel) :** le bHaptics Player lancé localement pour le TactSuit X40.

---

## 🚀 Installation & lancement (one-click)

1. Télécharge `GODS.exe` depuis la [dernière Release](../../releases/latest).
2. **Double-clique dessus.** C'est un exécutable **autonome** unique — aucun installeur, aucune dépendance à configurer.
3. Pour la **VR** : assure-toi que ton **runtime OpenXR est actif** (ex. lance le streaming Virtual Desktop *avant* de démarrer, ou dans les ~20 s suivant le lancement — le jeu bascule en VR dès qu'il détecte le casque). Sinon il tourne au bureau.

C'est tout.

---

## 🎮 Commandes

### Bureau
| Entrée | Action |
|---|---|
| **ZQSD / WASD** | Se déplacer |
| **Souris** | Regarder |
| **Espace** | Sauter |
| **F** | Activer le vol Iron Man (Espace = monter, C = descendre, Maj = boost) |
| **E** | Déployer / replier le parapente (en l'air) |
| **L** | Allumer/éteindre la torche à main gauche |
| **Clic gauche / Entrée** | Sélectionner / descendre d'une échelle (atterrir, etc.) |
| **Échap** | Remonter d'une échelle / annuler la pose |
| **Tab** | Ouvrir/fermer le menu Options |
| **Clic gauche** *(en mode pose)* | Poser une pièce / un bloc |
| **X** *(visé sur une pièce posée)* | La supprimer (ressource remboursée) |
| **G** *(visé sur une pièce posée)* | La ramasser et la déplacer |

### VR — sur une surface de planète
| Entrée | Action |
|---|---|
| **Stick gauche** | Marcher |
| **Stick droit ← →** | Pivoter (cran ou continu) |
| **A (droite)** | Sauter |
| **B (droite)** | Activer le vol Iron Man |
| **X (gauche)** | Déployer / replier le parapente (en l'air) |
| **Y (gauche)** | Allumer/éteindre la torche à main gauche |
| **☰ menu (gauche)** | Ouvrir/fermer le panneau Options worldspace |
| **Visée manette droite + gâchette** *(ou index)* | Interagir avec les panneaux / la montre |
| **Regarder son poignet gauche** | Ordinateur de poignet (inventaire, craft, pêche, construction…) |
| **Gâchette** *(en mode pose)* | Poser une pièce / un bloc |
| **Gâchette** *(canne équipée, bord de l'eau)* | Lancer / ferrer la ligne |
| **Grip (appui court)** *(visé sur une pièce)* | La supprimer (ressource remboursée) |
| **Grip (maintenu ~0,5 s)** *(visé sur une pièce)* | La ramasser et la déplacer |

### VR — galaxie / système / planète (orbite)
| Entrée | Action |
|---|---|
| **Visée + gâchette** | Sélectionner / descendre d'une échelle |
| **B (droite)** | Remonter d'une échelle |
| **Grip** | Saisir pour tourner/déplacer l'hologramme |
| **Stick droit (haut/bas)** | Zoom |

### Onglets de l'ordinateur de poignet
| Onglet | Contenu |
|---|---|
| **Sonde** | Sonde planétaire — biome, altitude, heure |
| **Temps** | Contrôle du temps (pause / accélération / temps réel) |
| **Sac** | Inventaire — objets par catégorie avec actions contextuelles (manger / décomposer / planter / poser / équiper) |
| **Bâtir** | Fonderie · Fabrication (36 recettes) · Blocs · Jardinage · Équipement de pêche |
| **Coop** | Coopération (héberger / rejoindre / quitter) |

---

## 👥 Coopération (optionnel)

Joue avec un ami — **opt-in**, pair-à-pair par IP (LAN, ou redirige le port **7711** pour Internet). Le monde est déterministe : seuls les joueurs, drones et loot transitent par le réseau.

- **Bureau :** appuie sur **F2** pour le panneau coop → **Héberger**, ou saisis l'IP de l'hôte et **Rejoindre**.
- **VR :** utilise la rangée **COOP** de la montre — Héberger / Rejoindre / Quitter (l'IP de l'hôte se règle une fois au bureau et est mémorisée).

L'hôte descend sur une planète ; l'invité atterrit au **même endroit** et vous explorez — et combattez les vagues — ensemble.

---

## 🔧 Compiler depuis les sources

Projet Godot standard.

1. Installe **Godot 4.6.2 (stable)** — rendu **Forward+**, **D3D12** sous Windows.
2. Ouvre le projet (`project.godot`) une fois dans l'éditeur pour importer les ressources.
3. **Lancer :**
   - Test bureau : `godot --path . --xr-mode off`
   - VR : simplement `godot --path .` (OpenXR s'initialise tout seul si un casque est présent).
4. **Exporter un exécutable Windows** (fichier autonome unique) :
   ```
   godot --headless --path . --export-release "Windows Desktop" build/GODS.exe
   ```
   (Nécessite les templates d'export Windows 4.6.2 installés.)

### Validation headless (sans casque)
- Compiler tous les scripts : `godot --headless --path . --editor --quit`
- Boot intégré : `godot --headless --path . --quit-after 200`

---

## 🧠 Points techniques

- **Un seul chemin d'échantillonnage partagé** (`PlanetGenerator.sample_elevation` / `sample_biome_*`) garantit la cohérence orbite ↔ surface ↔ végétation.
- **Génération de chunks hors-thread** (`WorkerThreadPool`) — pure, déterministe, avec insertion budgétée sur le thread principal et pooling de nodes.
- **Terrain sans couture** via normales analytiques par halo ; **geomorphing LOD** contre le popping.
- **Rebasage à origine flottante** pour la précision kilométrique à pied.
- **Formule de niveau de mer courbé** (`sea_y - r²/2R`) partagée entre le vertex shader de l'eau, la vérification de nage et la profondeur d'immersion — élimine les faux déclenchements « sous l'eau » sur terrain sec courbé.
- **Occlusion nuageuse de la géométrie céleste** — un include partagé `cloud_occlusion.gdshaderinc` réplique le champ nuageux dans chaque shader du dôme (étoiles, galaxie, lunes) via des uniforms globaux poussés à chaque frame ; la géométrie du sky-pass Forward+ ne peut pas être depth-clippée, donc l'occlusion est calculée analytiquement sur le GPU.
- **Catalogue de craft orienté données** (`CraftLibrary`, 36 recettes) dispatché par la montre avec filtrage par catégorie et affichage du coût en ressources.
- **Hydrologie** (flow map + érosion) bakée hors-thread au 1er accès planète ; rivières/lacs/cascades en découlent.
- **UI worldspace** (montre & panneau options) rendue dans des `SubViewport` sur des quads, pilotée par rayon/doigt réinjecté en événements souris synthétiques.
- **Audio DSP fait maison** alimentant des `AudioStreamGenerator` (oscillateurs, biquads, enveloppes, bruit).
- **Craft & construction déterministes** : chaque pièce posée, rocher miné et arbre planté est reproductible depuis le même seed + actions du joueur, avec comptabilité des ressources et remboursement à la suppression.

---

## 📁 Organisation du projet

```
scripts/        GDScript (générateurs, vues, joueur, XR, audio/, …)
shaders/        .gdshader / .gdshaderinc (terrain, eau, ciel, nuages, atmosphère, vignette, cascade, …)
scenes/         Main.tscn, WristComputer.tscn, …
addons/         addons tiers (le cas échéant)
project.godot   config moteur (autoloads, OpenXR, Jolt, D3D12)
```

Les commentaires sont en **français** ; les identifiants en **anglais**.

---

## 📜 Crédits & Licence

Créé par **Oli97430**. Réalisé avec [Godot Engine](https://godotengine.org) 4.6.2.

Licence : **[MIT](LICENSE)** pour le code & les assets propres au projet. Les add-ons sous `addons/` gardent leur licence (sky_3d : MIT ; Godot OpenXR Vendors : Apache-2.0).

🤖 Généré avec [Claude Code](https://claude.com/claude-code)
