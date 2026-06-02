class_name AmbientLayer
extends Node
## Phase 21 — base d'une couche d'ambiance. Possède UN SynthStream et un gain de CROSSFADE [0..1]
## lerpé en douceur (jamais de coupe sèche), appliqué DANS la synthèse => vrai silence à 0 (pas de
## stream qui tourne pour rien audible). Les sous-classes implémentent _setup() (config + état DSP),
## _fill() (synthèse temps réel) et _modulate() (réactions météo / temps). Mixage volontairement BAS.

const SR := 44100.0
const FADE_PER_SEC := 0.42      # ~2.4 s pour un crossfade complet (doux, contemplatif)

var stream: SynthStream
var gain := 0.0                 # gain de crossfade courant (lu dans _fill)
var _target := 0.0

func _ready() -> void:
	stream = SynthStream.new()
	add_child(stream)
	_setup()
	stream.fill_func = _fill
	stream.start()

# Active/désactive la couche : crossfade vers 1 ou 0.
func set_active(active: bool) -> void:
	_target = 1.0 if active else 0.0

func is_silent() -> bool:
	return gain < 0.001 and _target == 0.0

func _process(dt: float) -> void:
	gain = move_toward(gain, _target, FADE_PER_SEC * dt)
	_modulate(dt)

# --- À surcharger par les sous-classes ---

# Configure le stream (bus, volume de base, mix rate) + initialise les générateurs DSP.
func _setup() -> void:
	pass

# Écrit `frames` échantillons stéréo dans `buf` (multipliés par `gain`). Temps réel : rester léger.
func _fill(_buf: PackedVector2Array, _frames: int) -> void:
	pass

# Met à jour les paramètres lents (météo / heure) — appelé à la fréquence de frame, pas par échantillon.
func _modulate(_dt: float) -> void:
	pass
