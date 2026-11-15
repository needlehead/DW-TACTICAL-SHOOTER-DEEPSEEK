extends Node
## Background ambience (autoload). Plays every track in FOLDER in a shuffled order, crossfading between them,
## and reshuffles after each full pass without repeating the track that just ended. Tracks load one at a time.

const FOLDER := "res://my sounds/ambience/tracks/"

@export var volume_db := -12.0
@export var crossfade := 4.0  ## seconds of overlap between tracks

var _bag: Array[String] = []
var _last := ""
var _players: Array[AudioStreamPlayer] = []
var _current := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = &"Ambience"
		add_child(p)
		_players.append(p)
	play_next()


func _process(_delta: float) -> void:
	var p := _players[_current]
	if p.playing and p.get_playback_position() >= p.stream.get_length() - crossfade:
		play_next()


## Every ambience track, in folder order (works in exported builds too).
func tracks() -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(FOLDER):
		for f in ResourceLoader.list_directory(FOLDER):
			if f.get_extension() in ["ogg", "mp3", "wav"]:
				out.append(FOLDER + f)
	return out


## A shuffled pass over `all` that never starts with `last` (no back-to-back repeat across passes).
static func shuffled(all: Array[String], last: String) -> Array[String]:
	var bag: Array[String] = all.duplicate()
	bag.shuffle()
	if bag.size() > 1 and bag[0] == last:
		bag.push_back(bag.pop_front())
	return bag


func play_next() -> void:
	if _bag.is_empty():
		_bag = shuffled(tracks(), _last)
	if _bag.is_empty():
		return
	_last = _bag.pop_front()
	var old := _players[_current]
	_current = 1 - _current
	var p := _players[_current]
	p.stream = load(_last)
	p.volume_db = -60.0
	p.play()
	var t := create_tween().set_parallel()
	t.tween_property(p, "volume_db", volume_db, crossfade)
	if old.playing:
		t.tween_property(old, "volume_db", -60.0, crossfade)
		t.chain().tween_callback(old.stop)
