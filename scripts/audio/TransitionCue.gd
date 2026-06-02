class_name TransitionCue
extends Node
## Phase 22 — cue de transition d'échelle (remplace l'ancien tunnel de warp, retiré avec le vaisseau).
## Court & méditatif : un SWEEP doux (bruit passe-bande dont la fréquence centrale glisse) + un CHIME
## (deux sines en quinte, enveloppe lente). Sens selon descente (vers SURFACE = grave) / remontée
## (vers GALAXY = aigu). Très bas volume, 2D, routé via la reverb d'ambiance (sentiment d'espace).

# Déclenché par AudioEngine sur changement de Scale.
func trigger(from_scale: int, to_scale: int) -> void:
	if from_scale == to_scale:
		return
	var descending := to_scale > from_scale          # GALAXY(0) -> ... -> SURFACE(3)
	var ae := get_parent()
	if ae and ae.has_method("play_2d"):
		ae.play_2d(_synth(descending), -12.0, 1.0, "Ambient_World")

func _synth(descending: bool) -> AudioStreamWAV:
	var buf := SfxSynth.make_buffer(2.0)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var bp := Biquad.new(sr)
	var f_start := 320.0 if descending else 1500.0
	var f_end := 90.0 if descending else 3400.0
	var noise := SynthNoise.new(SynthNoise.Kind.PINK)
	var chime_f := 300.0 if descending else 740.0
	var ph1 := 0.0
	var ph2 := 0.0
	var inc1 := TAU * chime_f / sr
	var inc2 := TAU * chime_f * 1.5 / sr               # quinte au-dessus
	for i in n:
		var t := float(i) / float(n)
		if i % 64 == 0:                               # coefficients du filtre au CONTROL-RATE (perf synth)
			bp.set_params(Biquad.Type.BANDPASS, lerpf(f_start, f_end, t), 2.0)
		var sweep := bp.process(noise.next()) * 0.5
		ph1 += inc1
		if ph1 >= TAU:
			ph1 -= TAU
		ph2 += inc2
		if ph2 >= TAU:
			ph2 -= TAU
		var chime := (sin(ph1) + sin(ph2) * 0.6) * 0.18
		buf[i] = sweep * 0.5 + chime
	SfxSynth.apply_ar(buf, 0.25, 1.1)                 # montée douce + longue traîne
	return SfxSynth.to_wav(buf)
