extends SceneTree
## Phase 21 étape 2 — validation des primitives DSP (math pure, sans lecture audio) :
##   Osc (période sine), Noise (plages, pas de NaN), Biquad (atténuation passe-bas), Envelope (AR).

func _initialize() -> void:
	var sr := 44100.0
	print("===== DSP PRIMITIVES =====")

	# Osc sine 100 Hz sur 1 s : ~100 passages par zéro montants, valeurs dans [-1, 1].
	var o := Osc.new(sr, 100.0, Osc.Wave.SINE)
	var prev := 0.0
	var zc := 0
	var omin := 1.0
	var omax := -1.0
	for i in int(sr):
		var v := o.next()
		omin = minf(omin, v)
		omax = maxf(omax, v)
		if prev < 0.0 and v >= 0.0:
			zc += 1
		prev = v
	print("  Osc sine 100Hz : %d cycles/s (~100), range [%.2f, %.2f]" % [zc, omin, omax])

	# Bruits : plages bornées, non constants, pas de NaN.
	for c in [["blanc", SynthNoise.Kind.WHITE], ["rose", SynthNoise.Kind.PINK], ["brun", SynthNoise.Kind.BROWN]]:
		var n := SynthNoise.new(c[1], 12345)
		var nmin := 9.0
		var nmax := -9.0
		var asum := 0.0
		var nan := false
		for i in 30000:
			var v := n.next()
			if is_nan(v):
				nan = true
			nmin = minf(nmin, v)
			nmax = maxf(nmax, v)
			asum += absf(v)
		print("  Noise %-5s : range [%.2f, %.2f], |moy| %.3f, NaN=%s" % [c[0], nmin, nmax, asum / 30000.0, str(nan)])

	# Biquad passe-bas 200 Hz : atténue 4 kHz, laisse passer 50 Hz.
	var lp_hi := Biquad.new(sr)
	lp_hi.set_params(Biquad.Type.LOWPASS, 200.0, 0.7)
	var lp_lo := Biquad.new(sr)
	lp_lo.set_params(Biquad.Type.LOWPASS, 200.0, 0.7)
	var hi := Osc.new(sr, 4000.0)
	var lo := Osc.new(sr, 50.0)
	var rms_hi := 0.0
	var rms_lo := 0.0
	for i in 30000:
		var a := lp_hi.process(hi.next())
		rms_hi += a * a
		var b := lp_lo.process(lo.next())
		rms_lo += b * b
	rms_hi = sqrt(rms_hi / 30000.0)
	rms_lo = sqrt(rms_lo / 30000.0)
	print("  Biquad LP200 : RMS 4kHz=%.3f (atténué) | 50Hz=%.3f (passé)" % [rms_hi, rms_lo])

	# Envelope AR : monte puis redescend à 0.
	var e := Envelope.new(sr)
	e.set_ar(0.01, 0.02)
	e.trigger()
	var peak := 0.0
	var samples := 0
	var last := 1.0
	while e.is_active() and samples < int(sr):
		last = e.ar()
		peak = maxf(peak, last)
		samples += 1
	print("  Envelope AR(0.01,0.02) : pic=%.2f, durée=%.3f s, fin=%.3f" % [peak, samples / sr, last])
	print("DSP OK")
	quit()
