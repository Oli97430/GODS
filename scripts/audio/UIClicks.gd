class_name UIClicks
extends Node
## Phase 22 — clics UI de la montre, TRÈS subtils, non spatialisés (2D), volume très bas (-30 dB) :
##   POKE   : sine ~1000 Hz court ;
##   CONFIRM: doublé (deux pings rapprochés, le second +1 demi-ton) ;
##   CANCEL : sine ~600 Hz légèrement descendant, enveloppe douce.
## Les WAV sont synthétisés UNE fois (cachés). Branchés sur les signaux du WristComputer.

var _wrist: Node
var _poke: AudioStreamWAV
var _confirm: AudioStreamWAV
var _cancel: AudioStreamWAV

func _ready() -> void:
	_poke = _tone(760.0, 0.08, 0.001, 0.07, -0.05)   # « tok » doux (moins perçant qu'un bip 1 kHz)
	_confirm = _make_confirm()
	_cancel = _tone(600.0, 0.14, 0.004, 0.12, -0.06)

func _process(_dt: float) -> void:
	if _wrist == null or not is_instance_valid(_wrist):
		_acquire()

func _acquire() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var w := scene.find_child("WristComputer", true, false)
	if w == null:
		return
	_wrist = w
	if w.has_signal("ui_poke") and not w.ui_poke.is_connected(_on_poke):
		w.ui_poke.connect(_on_poke)
	if w.has_signal("ui_confirm") and not w.ui_confirm.is_connected(_on_confirm):
		w.ui_confirm.connect(_on_confirm)
	if w.has_signal("ui_cancel") and not w.ui_cancel.is_connected(_on_cancel):
		w.ui_cancel.connect(_on_cancel)

func _on_poke() -> void:
	_play(_poke)

func _on_confirm() -> void:
	_play(_confirm)

func _on_cancel() -> void:
	_play(_cancel)

func _play(wav: AudioStreamWAV) -> void:
	var ae := get_parent()
	if ae and ae.has_method("play_2d"):
		ae.play_2d(wav, -18.0, 1.0, "SFX")

# Sine avec glissando relatif (glide) + enveloppe AR.
func _tone(freq: float, dur: float, atk: float, rel: float, glide: float) -> AudioStreamWAV:
	var buf := SfxSynth.make_buffer(dur)
	var n := buf.size()
	var sr := float(SfxSynth.SR)
	var ph := 0.0
	var ph2 := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f := freq * (1.0 + glide * t)
		ph += TAU * f / sr
		ph2 += TAU * f * 2.0 / sr
		var s := sin(ph) * 0.6 + sin(ph2) * 0.18   # octave discrète => moins « bip » pur, plus « tok »
		buf[i] = s / (1.0 + absf(s) * 0.6)          # soft-clip doux
	SfxSynth.apply_ar(buf, atk, rel)
	SfxSynth.normalize_peak(buf, 0.6)
	return SfxSynth.to_wav(buf)

# Deux pings rapprochés (le second +1 demi-ton) — confirmation.
func _make_confirm() -> AudioStreamWAV:
	var sr := float(SfxSynth.SR)
	var buf := SfxSynth.make_buffer(0.20)
	_ping(buf, 0, int(0.07 * sr), 1000.0, sr)
	_ping(buf, int(0.06 * sr), int(0.07 * sr), 1000.0 * pow(2.0, 1.0 / 12.0), sr)
	return SfxSynth.to_wav(buf)

func _ping(buf: PackedFloat32Array, start: int, length: int, freq: float, sr: float) -> void:
	var ph := 0.0
	var ph2 := 0.0
	for k in length:
		var i := start + k
		if i >= buf.size():
			break
		ph += TAU * freq / sr
		ph2 += TAU * freq * 2.0 / sr
		var env := 1.0 - float(k) / float(length)
		buf[i] += (sin(ph) * 0.5 + sin(ph2) * 0.15) * env   # + octave => timbre de cloche
