class_name AmbientWater
extends AudioStreamPlayer3D
## Phase 21 — CLAPOTIS positionnel (bus Ambient_World) : bruit filtré bas (eau qui remue) + impacts
## doux rares. AudioStreamPlayer3D => panné/atténué par la caméra active (le SEUL son positionnel,
## le reste de l'ambiance étant stéréo 2D pour éviter la fatigue de tracking en VR). Position et gain
## de proximité pilotés par AudioEngine (au niveau de la mer, près du joueur en zone basse/côtière).

const SR := 44100.0

var _pb: AudioStreamGeneratorPlayback
var _buf := PackedVector2Array()
var _lp: Biquad
var _lpR: Biquad          # 2e passe-bas indépendant (droite) => clapotis large
var _brown := 0.0
var _brownR := 0.0
var _rng := RandomNumberGenerator.new()
var _imp: Envelope
var _imp_timer := 1.0
var _gain := 0.0
var _cur := 0.0

func _ready() -> void:
	var g := AudioStreamGenerator.new()
	g.mix_rate = SR
	g.buffer_length = 0.6   # marge anti-sous-alimentation (son "haché") lors des à-coups de frame près du rivage
	stream = g
	bus = "Ambient_World"
	volume_db = -8.0
	unit_size = 6.0
	max_distance = 60.0
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_lp = Biquad.new(SR)
	_lp.set_params(Biquad.Type.LOWPASS, 950.0, 0.7)
	_lpR = Biquad.new(SR)
	_lpR.set_params(Biquad.Type.LOWPASS, 950.0, 0.7)
	_imp = Envelope.new(SR)
	_imp.set_ar(0.01, 0.4)
	_rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS   # remplissage continu même en pause (anti-coupure)
	play()
	_pb = get_stream_playback()

# Gain de proximité [0..1] : 0 = loin de l'eau (silencieux), 1 = au bord.
func set_proximity(gv: float) -> void:
	_gain = clampf(gv, 0.0, 1.0)

func _process(dt: float) -> void:
	_cur = move_toward(_cur, _gain, 0.7 * dt)
	_imp_timer -= dt
	if _imp_timer <= 0.0:
		_imp_timer = _rng.randf_range(0.5, 1.8)
		if _cur > 0.05 and not _imp.is_active():
			_imp.trigger()
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	if _buf.size() != n:
		_buf.resize(n)
	var gg := _cur
	if gg < 0.0008:                      # loin de l'eau : zéro synthèse (perf)
		for i in n:
			_buf[i] = Vector2.ZERO
		_pb.push_buffer(_buf)
		return
	for i in n:
		_brown += (_rng.randf() * 2.0 - 1.0) * 0.02
		_brown = clampf(_brown, -1.0, 1.0)
		var body := _lp.process(_brown * 3.2)
		var imp := 0.0
		if _imp.is_active():
			imp = _imp.ar() * (_rng.randf() * 2.0 - 1.0) * 0.5   # éclaboussure (centrée)
		var s := (body * 0.5 + imp) * gg * 0.5
		# MONO : un AudioStreamPlayer3D spatialise déjà selon l'écoute => le « stéréo » L/R décorrélé était gâché (CPU pur).
		_buf[i] = Vector2(s, s)
	_pb.push_buffer(_buf)
