class_name SynthStream
extends AudioStreamPlayer
## Phase 21 — encapsule un AudioStreamGenerator + son remplissage temps réel. On lui donne une
## fonction de génération `fill_func(buf: PackedVector2Array, frames: int)` qui ÉCRIT `frames`
## échantillons stéréo dans `buf` ; SynthStream les pousse au playback chaque frame. Un buffer est
## réutilisé (zéro allocation par frame). UN seul stream par couche => économie de voix (brief).

var fill_func: Callable                       # func(buf: PackedVector2Array, frames: int) -> void
var mix_rate := 44100.0

var _pb: AudioStreamGeneratorPlayback
var _buf := PackedVector2Array()
var _started := false

# Configure le générateur (bus, volume de base, sample rate, longueur de buffer). À appeler avant start().
func setup(p_bus: String, p_volume_db := -18.0, p_mix_rate := 44100.0, p_buffer := 0.3) -> void:
	mix_rate = p_mix_rate
	var g := AudioStreamGenerator.new()
	g.mix_rate = p_mix_rate
	g.buffer_length = p_buffer
	stream = g
	bus = p_bus
	volume_db = p_volume_db

func start() -> void:
	if _started:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS   # le remplissage doit continuer même si l'arbre se met en pause (sinon buffer vidé => clic/coupure)
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
