class_name CreatureVoice
extends RefCounted
## Phase 22 — « voix » d'une espèce de faune : paramètres DÉTERMINISTES dérivés du seed espèce
## (species.key) => une espèce sonne toujours pareil (timbre/fréquence/enveloppe), mais chaque appel
## a une micro-variation vivante. Appels DOUX, jamais alarmants. La créature qui FUIT reste SILENCIEUSE.

# Paramètres voix déterministes pour une clé d'espèce.
static func voice_params(species_key: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = species_key * 2654435761 + 8311
	return {
		"wave": rng.randi() % 3,                       # 0 sine, 1 triangle, 2 saw doux
		"freq": rng.randf_range(220.0, 880.0),         # fréquence centrale de l'appel
		"glide": rng.randf_range(-0.18, 0.22),         # glissando relatif (montant/descendant)
		"vibrato_hz": rng.randf_range(4.0, 8.0),
		"vibrato_amt": rng.randf_range(0.0, 0.045),    # profondeur de vibrato (relatif)
		"dur": rng.randf_range(0.18, 0.55),            # durée de l'appel
		"attack": rng.randf_range(0.01, 0.06),
		"release": rng.randf_range(0.06, 0.26),
		"call_chance": rng.randf_range(0.12, 0.32),    # proba par évaluation (toutes les ~6 s)
		"volume_db": rng.randf_range(-11.0, -6.0),
	}

# Synthétise l'appel one-shot (AudioStreamWAV) — micro-variation par appel (désaccord + vibrato libres).
static func synth(v: Dictionary) -> AudioStreamWAV:
	var buf := SfxSynth.make_buffer(v.get("dur", 0.3))
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var f0: float = v.get("freq", 440.0) * (1.0 + randf_range(-0.03, 0.03))
	var glide: float = v.get("glide", 0.0)
	var vib_hz: float = v.get("vibrato_hz", 6.0)
	var vib_amt: float = v.get("vibrato_amt", 0.0)
	var wave: int = v.get("wave", 0)
	var ph := 0.0
	var ph2 := 0.0     # désaccord (chorus) => appel plus ample
	var pho := 0.0     # octave (harmonique douce) => timbre plus riche
	var vph := 0.0
	for i in n:
		var t := float(i) / float(n)
		vph += TAU * vib_hz / sr
		var f := f0 * (1.0 + glide * t) * (1.0 + vib_amt * sin(vph))
		ph += TAU * f / sr
		if ph >= TAU:
			ph -= TAU
		ph2 += TAU * f * 1.006 / sr
		if ph2 >= TAU:
			ph2 -= TAU
		pho += TAU * f * 2.0 / sr
		if pho >= TAU:
			pho -= TAU
		var w1 := sin(ph)
		var w2 := sin(ph2)
		if wave == 1:
			w1 = 4.0 * absf(ph / TAU - 0.5) - 1.0       # triangle
			w2 = 4.0 * absf(ph2 / TAU - 0.5) - 1.0
		elif wave == 2:
			w1 = (ph / PI - 1.0) * 0.6                  # saw doux
			w2 = (ph2 / PI - 1.0) * 0.6
		var s := w1 * 0.5 + w2 * 0.4 + sin(pho) * 0.14
		buf[i] = s * 0.8
	SfxSynth.apply_ar(buf, v.get("attack", 0.03), v.get("release", 0.15))
	SfxSynth.normalize_peak(buf, 0.8)   # timbre enrichi, loudness préservée (la variation vient du volume_db par appel)
	return SfxSynth.to_wav(buf)
