extends AudioStreamPlayer
## Musique de fond en lecture aléatoire continue (playlist perso, Nightwish + BO WoW).
## Chaque piste est chargée À LA DEMANDE depuis res://music/ (mémoire légère : une seule
## en RAM), enchaîne sur la suivante à la fin, et la playlist est re-mélangée quand elle
## est épuisée (lecture sans fin). Indépendant de l'échelle de jeu (toujours actif).

const MUSIC_DIR := "res://music/"
const TRACKS := [
	"01 - Ghost love score.mp3",
	"01 - The poet and the pendulum.mp3",
	"02 - 10th man down.mp3",
	"02 - Beauty and the beast.mp3",
	"02 - Wish i had an angel.mp3",
	"04 - Planet hell.mp3",
	"04 - Wanderlust.mp3",
	"World Of Warcraft - 04 - Song Of Elune (Exclusive Track).mp3",
	"World Of Warcraft - 05 - Echoes Of The Past (Exclusive Track).mp3",
	"World Of Warcraft - 22 - Teldrassil.mp3",
	"World Of Warcraft - 24 - Moonfall.mp3",
]

var _order: Array[int] = []
var _pos := 0

# Désactivé : la musique/ambiance GÉNÉRATIVE (phase 21) remplace la playlist MP3 importée
# (WoW / Nightwish). Remettre à true pour réentendre les pistes de res://music/.
const ENABLED := false

func _ready() -> void:
	if not ENABLED:
		return                  # ne joue plus les bandes-son importées (musique générative à la place)
	volume_db = -10.0           # fond sonore (ne couvre pas le reste)
	autoplay = false
	finished.connect(_advance)  # enchaîne la piste suivante à la fin
	_reshuffle()
	_play_current()

func _reshuffle() -> void:
	_order.clear()
	for i in TRACKS.size():
		_order.append(i)
	_order.shuffle()
	_pos = 0

func _play_current() -> void:
	if _order.is_empty():
		return
	var s := _load_mp3(MUSIC_DIR + TRACKS[_order[_pos]])
	if s == null:
		_advance()   # piste introuvable : on saute à la suivante
		return
	stream = s
	play()

func _advance() -> void:
	_pos += 1
	if _pos >= _order.size():
		_reshuffle()   # playlist épuisée -> nouveau mélange, lecture sans fin
	_play_current()

# Charge un MP3 via ses octets : pas besoin de l'import Godot, marche tant que le
# fichier existe sur le disque (res:// résolu vers le FS réel en lancement --path).
func _load_mp3(path: String) -> AudioStreamMP3:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[MusicPlayer] piste introuvable : " + path)
		return null
	var s := AudioStreamMP3.new()
	s.data = f.get_buffer(f.get_length())
	f.close()
	return s
