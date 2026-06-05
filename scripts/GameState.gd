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

# Vrai tant que l'écran de DÉPART (« choisir un système ») est ouvert au lancement : gèle la nav galaxie.
var start_menu_open: bool = false

# --- Tableau de bord COMBAT (phase 26 CP3) : blackboard partagé joueur ↔ vagues ↔ HUD/montre. ---
# Écrit par PlayerController (PV/mort) et WaveManager (vague/score) ; lu par CombatHUD (bureau) + WristComputer (VR).
var combat_active: bool = false   # une arme est équipée (combat opt-in en cours)
var combat_hp: float = 100.0      # points de vie courants du joueur
var combat_hp_max: float = 100.0  # PV max
var combat_dead: bool = false     # joueur éliminé (réapparition en cours)
var combat_wave: int = 0          # numéro de la vague courante
var combat_score: int = 0         # drones détruits dans la session de combat courante
var combat_result_wave: int = 0   # vague atteinte (figée à la mort) — pour l'écran de fin de run
var combat_result_score: int = 0  # score final (figé à la mort)
var combat_overshield: float = 0.0     # PV de bouclier en sus (améliorations ramassées) — absorbés avant les PV
var combat_dmg_mult: float = 1.0       # multiplicateur de dégâts (améliorations ramassées)
var combat_firerate_mult: float = 1.0  # multiplicateur de cadence de tir (améliorations ramassées)
