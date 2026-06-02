class_name NameGenerator
extends RefCounted
## Noms propres PROCÉDURAUX & DÉTERMINISTES (phase 19.5) — systèmes, planètes, lunes.
## Génération SYLLABIQUE par phonotactique (PAS de Markov, PAS de corpus, PAS de table écrite à la main) :
## chaque palette linguistique définit des phonèmes (onsets / nuclei / codas) + des biais, et un nom
## = concaténation de syllabes onset+nucleus+coda sous règles STRICTES (2-3 syllabes, onsets = consonnes
## PURES, pas de cluster après coda, pas de double diphtongue, garde-fou de longueur, pas de triplet,
## majuscule initiale). Ton CONTEMPLATIF : aucun code/numéro/tiret.
##
## Déterminisme : generate_name(seed, palette) renvoie TOUJOURS le même nom. La palette d'un système
## vient de sa POSITION galactique (bruit cellulaire) => régions cohérentes (systèmes proches = même
## palette = sense of place). Tout est défini EN CODE (aucun asset texte importé).

const MAX_LEN := 10   # garde-fou : noms courts & lisibles

# --- 5 palettes contrastées. onsets = attaques (CONSONNES pures / clusters), nuclei = voyelles ou
#     diphtongues (2 lettres), codas = consonnes finales. La multiplicité = la fréquence (caractère). ---
const PALETTES := [
	{   # 0 — COULANTE : liquides l/r/m/n, voyelles douces (Veloryne, Aelinor, Solanthe)
		"name": "Coulante",
		"onsets": ["", "l", "r", "m", "n", "v", "l", "r", "n", "th"],
		"nuclei": ["a", "e", "o", "y", "a", "e", "o", "ae", "io"],
		"codas": ["n", "r", "l", "th"],
		"syl_min": 2, "syl_max": 3, "coda_prob": 0.22, "end_coda_prob": 0.40,
	},
	{   # 1 — SIFFLÉE : s/sh/z dominantes (Sashira, Zessane, Ostralys)
		"name": "Sifflee",
		"onsets": ["s", "sh", "z", "s", "z", "st", "s", "sh"],
		"nuclei": ["a", "e", "i", "a", "e", "i", "ai", "o"],
		"codas": ["n", "s", "sh"],
		"syl_min": 2, "syl_max": 3, "coda_prob": 0.18, "end_coda_prob": 0.38,
	},
	{   # 2 — DURE : occlusives k/t/g/d, voyelles ouvertes (Karak, Tothren, Gandrak)
		"name": "Dure",
		"onsets": ["k", "t", "g", "d", "kr", "gr", "tr", "k", "t", "g"],
		"nuclei": ["a", "o", "e", "a", "o", "u", "au"],
		"codas": ["k", "t", "n", "r", "g"],
		"syl_min": 2, "syl_max": 3, "coda_prob": 0.40, "end_coda_prob": 0.58,
	},
	{   # 3 — SOUFFLÉE : fricatives f/h, voyelles fermées (Whephar, Halyn, Faelir)
		"name": "Soufflee",
		"onsets": ["f", "h", "ph", "fl", "f", "h", "wh", "fl"],
		"nuclei": ["e", "y", "a", "i", "ae", "e", "y"],
		"codas": ["r", "n", "l", "f"],
		"syl_min": 2, "syl_max": 3, "coda_prob": 0.28, "end_coda_prob": 0.45,
	},
	{   # 4 — VOYELLIQUE : voyelles longues & diphtongues, attaques rares (Aionae, Oroai, Eolyn)
		"name": "Voyellique",
		"onsets": ["", "", "l", "n", "r", "v", "y"],
		"nuclei": ["ai", "ae", "eo", "oa", "io", "a", "e", "o", "y", "ei"],
		"codas": ["n"],
		"syl_min": 2, "syl_max": 3, "coda_prob": 0.16, "end_coda_prob": 0.30,
	},
]

# Suffixes ordinaux POÉTIQUES pour les lunes (pas "I/II/III" administratifs).
const MOON_ORDINALS := ["Prime", "Seconde", "Tierce", "Quarte", "Quinte", "Sexte", "Septime", "Octave"]

const REGION_SEED := 1337           # graine FIXE de la galaxie (régionalisation stable)
const REGION_FREQ := 0.028          # basse fréquence : grandes régions linguistiques contiguës
static var _region_a: FastNoiseLite
static var _region_b: FastNoiseLite

# --- API ---

# Nom propre déterministe pour un seed + une palette. Même (seed, palette) => même nom, toujours.
static func generate_name(seed_val: int, palette_id: int) -> String:
	var p: Dictionary = PALETTES[clampi(palette_id, 0, PALETTES.size() - 1)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val * 2654435761 + palette_id * 40503 + 11   # décorrèle seed/palette
	var target: int = rng.randi_range(p.syl_min, p.syl_max)
	var s := ""
	var built := 0
	var prev_coda := false
	var prev_diph := false
	var prev_onset_ini := ""
	for i in target:
		var onset: String = _pick(rng, p.onsets)
		if prev_coda and onset.length() >= 2:
			onset = ""                                  # pas de cluster juste après une coda (imprononçable)
		if i == 0 and onset == "" and palette_id != 4:
			onset = _pick(rng, p.onsets)                # début par une consonne (sauf palette voyellique)
		# Évite de répéter la même consonne d'attaque d'une syllabe à l'autre (anti « Shasha », « Whywhy »).
		if onset != "" and prev_onset_ini != "" and onset[0] == prev_onset_ini:
			var alt: String = _pick(rng, p.onsets)
			if alt == "" or alt[0] != prev_onset_ini:
				onset = alt
		var nucleus: String = _pick(rng, p.nuclei)
		if prev_diph and nucleus.length() >= 2:
			nucleus = _pick_single(rng, p.nuclei)       # jamais 2 diphtongues d'affilée
		var coda := ""
		var prob: float = p.end_coda_prob if i == target - 1 else p.coda_prob
		if rng.randf() < prob:
			coda = _pick(rng, p.codas)
		var piece: String = onset + nucleus + coda
		if built >= p.syl_min and s.length() + piece.length() > MAX_LEN:
			break                                       # garde-fou longueur (court & lisible)
		s += piece
		built += 1
		prev_coda = coda != ""
		prev_diph = nucleus.length() >= 2
		if onset != "":
			prev_onset_ini = onset[0]
	s = _cleanup(s)
	if s.length() < 3:
		s += _pick_single(rng, p.nuclei)                # garde-fou (jamais de nom trop court)
	return s.substr(0, 1).to_upper() + s.substr(1)

# Palette d'un système d'après sa POSITION galactique : bruit CELLULAIRE (Voronoi) => régions
# contiguës de même palette (systèmes proches partagés), régions distantes différentes.
static func palette_for_galactic_position(pos: Vector3) -> int:
	if _region_a == null:
		_region_a = FastNoiseLite.new()
		_region_a.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_region_a.seed = REGION_SEED
		_region_a.frequency = REGION_FREQ
		_region_b = FastNoiseLite.new()
		_region_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_region_b.seed = REGION_SEED + 9176   # second champ indépendant
		_region_b.frequency = REGION_FREQ
	# Deux champs simplex LISSES et indépendants ; on prend l'ANGLE atan2(b, a). Cet angle est
	# ~UNIFORME sur [0, TAU) (=> les 5 palettes sont ÉQUILIBRÉES) tout en variant DOUCEMENT dans
	# l'espace (=> régions linguistiques CONTIGUËS : les systèmes voisins partagent leur palette).
	# Bien meilleur que la valeur de cellule brute (concentrée => une palette dominait). Déterministe.
	var a: float = _region_a.get_noise_3dv(pos)
	var b: float = _region_b.get_noise_3dv(pos)
	var u: float = (atan2(b, a) + PI) / TAU   # [0,1) ~uniforme
	return clampi(int(u * float(PALETTES.size())), 0, PALETTES.size() - 1)

# Nom de lune : par défaut suffixe ordinal poétique du nom de la planète (« Veloryne Prime »).
# Cohérent & déterministe (le rang vient de l'index de la lune). 'own_name' force un nom propre.
static func moon_name(planet_name: String, moon_index: int, planet_seed: int, palette_id: int, own_name: bool = false) -> String:
	if own_name:
		return generate_name(planet_seed + 7919 * (moon_index + 1), palette_id)
	var ord: String = MOON_ORDINALS[moon_index] if moon_index < MOON_ORDINALS.size() else str(moon_index + 1)
	return planet_name + " " + ord

static func palette_name(palette_id: int) -> String:
	return PALETTES[clampi(palette_id, 0, PALETTES.size() - 1)].name

# --- Helpers ---

static func _pick(rng: RandomNumberGenerator, arr: Array) -> String:
	return arr[rng.randi() % arr.size()]

# Pioche une voyelle SIMPLE (longueur 1) dans une liste de nuclei (repli : pioche normale).
static func _pick_single(rng: RandomNumberGenerator, arr: Array) -> String:
	var singles: Array = []
	for x in arr:
		if x.length() == 1:
			singles.append(x)
	if singles.is_empty():
		return _pick(rng, arr)
	return singles[rng.randi() % singles.size()]

# Nettoyage prononçabilité : pas plus de 2 lettres identiques d'affilée.
static func _cleanup(s: String) -> String:
	var out := ""
	for i in s.length():
		var ch := s[i]
		if out.length() >= 2 and out[out.length() - 1] == ch and out[out.length() - 2] == ch:
			continue
		out += ch
	return out
