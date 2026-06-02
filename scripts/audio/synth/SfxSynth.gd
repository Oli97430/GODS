class_name SfxSynth
extends RefCounted
## Phase 22 — synthèse de bursts COURTS en PCM, 100% procédural (AUCUN fichier importé). Les sons
## one-shot (pas, clics UI, appels de faune, cue de transition) construisent un buffer de floats
## [-1,1] avec les primitives phase 21 (SynthNoise / Osc / Biquad / Envelope), puis l'emballent ici
## en AudioStreamWAV 16-bit mono. Joué sur un AudioStreamPlayer(3D) poolé => positionnel, pitch
## variable, auto-stop, ZÉRO CPU continu (contrairement à un AudioStreamGenerator qui tournerait).

const SR := 44100

# Emballe un buffer de floats [-1,1] en AudioStreamWAV 16-bit mono (sans boucle). Synthèse pure.
static func to_wav(buf: PackedFloat32Array, mix_rate := SR) -> AudioStreamWAV:
	var n := buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = mix_rate
	w.stereo = false
	w.loop_mode = AudioStreamWAV.LOOP_DISABLED
	w.data = data
	return w

# Applique une enveloppe attack/release (secondes) à un buffer, en place (anti-clic + forme douce).
static func apply_ar(buf: PackedFloat32Array, attack_s: float, release_s: float, mix_rate := SR) -> void:
	var n := buf.size()
	var atk := maxi(int(attack_s * mix_rate), 1)
	var rel := maxi(int(release_s * mix_rate), 1)
	for i in n:
		var e := 1.0
		if i < atk:
			e = float(i) / float(atk)
		var tail := n - i
		if tail < rel:
			e = minf(e, float(tail) / float(rel))
		buf[i] *= e

# Crée un buffer vide de 'dur' secondes (à remplir par l'appelant).
static func make_buffer(dur: float, mix_rate := SR) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(maxi(int(dur * mix_rate), 1))
	return buf
