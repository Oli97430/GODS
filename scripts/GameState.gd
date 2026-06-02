extends Node
## Autoload global : état partagé entre toutes les échelles de navigation.
## Sert de socle pour emboîter les phases 2 (système) et 3 (planète).
## En phase 1, seule l'échelle GALAXY est réellement implémentée.

# Échelles de navigation (galaxie -> système -> planète orbitale -> surface au sol).
enum Scale { GALAXY, SYSTEM, PLANET, SURFACE }

# Graine globale déterministe : même graine => galaxie identique à chaque lancement.
# Réglable ici (ou par code avant la génération) pour obtenir une autre galaxie.
var global_seed: int = 1337

# Échelle courante de l'explorateur (toujours GALAXY en phase 1).
var current_scale: Scale = Scale.GALAXY

# Vrai lorsqu'un runtime XR + casque sont actifs. Renseigné par XRManager au démarrage.
var xr_active: bool = false

# Toggle global (phase 4) : active/désactive d'un coup l'atmosphère et les nuages
# des planètes (mode perf casque bas de gamme). Lu en continu par PlanetAtmosphere.
var atmosphere_enabled: bool = true

# Vrai quand le menu Options (overlay bureau) est ouvert : bloque l'entrée jeu (locomotion/navigation).
var options_open: bool = false
