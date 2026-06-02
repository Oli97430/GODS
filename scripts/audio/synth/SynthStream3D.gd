class_name SynthStream3D
extends AudioStreamPlayer3D
## Phase 22 — variante POSITIONNELLE (3D) de SynthStream : un AudioStreamGenerator alimenté en temps
## réel, attaché à une position monde mise à jour de l'extérieur (POIAudio). Même patron de remplissage.
## Contenu mono (même valeur G/D) => spatialisation propre par le moteur 3D.

var fill_func: Callable
var mix_rate := 44100.0

var _pb: AudioStreamGeneratorPlayback
var _buf := PackedVector2Array()
var _started := false

func setup(p_bus: String, p_volume_db := -18.0, p_mix_rate := 44100.0, p_buffer := 0.3) -> void:
	mix_rate = p_mix_rate
	var g := AudioStreamGenerator.new()
	g.mix_rate = p_mix_rate
	g.buffer_length = p_buffer
	stream = g
	bus = p_bus
	volume_db = p_volume_db
	max_distance = 70.0
	unit_size = 8.0
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE

func start() -> void:
	if _started:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS   # remplissage continu même en pause (anti-coupure)
	play()
	_pb = get_stream_playback()
	_started = true

func _process(_dt: float) -> void:
	if _pb == null or not fill_func.is_valid():
		return
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	if _buf.size() != n:
		_buf.resize(n)
	fill_func.call(_buf, n)
	_pb.push_buffer(_buf)
