extends SceneTree
## Phase 22 — sanity de la SYNTHÈSE one-shot (PCM) : buffers non vides, échantillons dans [-1,1],
## aucun NaN. Ne joue rien (vérifie juste que les générateurs produisent des AudioStreamWAV valides).

func _check(wav: AudioStreamWAV, name: String) -> bool:
	if wav == null:
		print("  %-12s : NULL" % name)
		return false
	var d := wav.data
	var n := d.size() / 2
	var mn := 1.0
	var mx := -1.0
	var nan := false
	for i in n:
		var s := d.decode_s16(i * 2) / 32768.0
		if s != s:
			nan = true
		mn = minf(mn, s)
		mx = maxf(mx, s)
	print("  %-12s : %5d samples, range [%.2f, %.2f], NaN=%s" % [name, n, mn, mx, str(nan)])
	return n > 0 and not nan

func _initialize() -> void:
	print("===== PHASE 22 — synthèse one-shot =====")
	var ok := true
	# Appel de faune (voix déterministe par seed espèce).
	var v := CreatureVoice.voice_params(12345)
	ok = _check(CreatureVoice.synth(v), "call") and ok
	# Pas par biome.
	var fs := Footsteps.new()
	var names := {0: "ocean", 1: "beach", 2: "plains", 3: "forest", 4: "rock", 5: "snow"}
	for b in [PlanetGenerator.Biome.PLAINS, PlanetGenerator.Biome.ROCK, PlanetGenerator.Biome.BEACH, PlanetGenerator.Biome.SNOW]:
		ok = _check(fs._synth(b), "step-" + names[b]) and ok
	fs.free()
	# Clics UI.
	var ui := UIClicks.new()
	ui._ready()
	ok = _check(ui._poke, "poke") and ok
	ok = _check(ui._confirm, "confirm") and ok
	ok = _check(ui._cancel, "cancel") and ok
	ui.free()
	# Cue de transition (descente / remontée).
	var tc := TransitionCue.new()
	ok = _check(tc._synth(true), "trans-down") and ok
	ok = _check(tc._synth(false), "trans-up") and ok
	tc.free()
	print("\nTOUT VALIDE (non vide, dans la plage, pas de NaN) : %s" % str(ok))
	quit()
