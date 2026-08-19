class_name UiSound
extends Node

## Minimal interaction audio. The kit ships no audio files yet, so the cues are
## synthesised at load: short tones and noise bursts that give taps, purchases
## and burns something to land on. Gated behind `ui_sound_enabled` so the game
## can ship silent until authored sound arrives.

const SAMPLE_RATE := 22050
const VOICES := 4

## cue -> [start_hz, end_hz, seconds, waveform, volume]. Waveforms: "sine",
## "square", "noise".
const CUES := {
	"tap": [640.0, 640.0, 0.045, "square", 0.16],
	"accept": [520.0, 830.0, 0.16, "sine", 0.3],
	"buy": [900.0, 1350.0, 0.13, "square", 0.22],
	"burn": [200.0, 80.0, 0.26, "noise", 0.26],
	# Quiet multiplier ticks. Three pitches so a cascade climbs instead of
	# repeating the same blip.
	"proc": [480.0, 720.0, 0.07, "sine", 0.2],
	"proc_mid": [620.0, 920.0, 0.07, "sine", 0.22],
	"proc_high": [780.0, 1180.0, 0.08, "sine", 0.24],
	"complete": [660.0, 1320.0, 0.34, "sine", 0.32],
	"error": [240.0, 150.0, 0.2, "square", 0.24],
	# Two-tone klaxon for the rig's heat beacon: a long fall, loud enough to be
	# read as a warning rather than a confirmation.
	"alarm": [880.0, 420.0, 0.45, "square", 0.3],
	# Terminal keystroke. Fires several times a second while output streams, so it
	# has to be very quiet and very short.
	"key": [1500.0, 1350.0, 0.016, "square", 0.05],
}

## Cues made of several notes in a row rather than one swept tone. An award needs
## to sound like more than a confirmation, and a rising arpeggio is the shortest
## thing that reads as one: the notes run up, the last one rings out.
const SEQUENCES := {
	"combo": {
		"notes": [659.0, 880.0],
		"note_seconds": 0.07,
		"tail_seconds": 0.18,
		"waveform": "sine",
		"volume": 0.28,
	},
	"fanfare": {
		"notes": [523.0, 659.0, 784.0, 1047.0],
		"note_seconds": 0.09,
		"tail_seconds": 0.42,
		"waveform": "sine",
		"volume": 0.34,
	},
}

static var _instance: UiSound = null

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _next_voice: int = 0


## Called once by the main scene. Later calls are ignored so the service
## survives scene reloads without stacking players.
static func attach(root: Node) -> void:
	if _instance != null and is_instance_valid(_instance):
		return
	if not FeatureFlags.is_enabled("ui_sound_enabled"):
		return
	_instance = UiSound.new()
	_instance.name = "UiSound"
	root.add_child(_instance)


static func play(cue: String) -> void:
	if _instance == null or not is_instance_valid(_instance):
		return
	_instance._play_cue(cue)


## A cascade tick. `depth` is how many named procs have already landed, so the
## pitch climbs as the batch gets more interesting.
static func play_proc(depth: int = 0) -> void:
	if depth >= 4:
		play("proc_high")
	elif depth >= 2:
		play("proc_mid")
	else:
		play("proc")


func _ready() -> void:
	for i in range(VOICES):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)
	for cue in CUES:
		_streams[cue] = _build_stream(CUES[cue])
	for cue in SEQUENCES:
		_streams[cue] = _build_sequence(SEQUENCES[cue])


func _play_cue(cue: String) -> void:
	if not _streams.has(cue):
		return
	# Round-robin voices so a rapid sequence of taps does not cut itself off.
	var player: AudioStreamPlayer = _players[_next_voice]
	_next_voice = (_next_voice + 1) % _players.size()
	player.stream = _streams[cue]
	player.play()


func _build_stream(spec: Array) -> AudioStreamWAV:
	return _wav(_render(float(spec[0]), float(spec[1]), float(spec[2]), str(spec[3]), float(spec[4])))


## Renders each note flat (no sweep) back to back. Every note carries the same
## fast attack and full decay as a single cue, so the run-up does not smear.
func _build_sequence(spec: Dictionary) -> AudioStreamWAV:
	var notes: Array = spec.get("notes", [])
	var note_seconds: float = float(spec.get("note_seconds", 0.1))
	var tail_seconds: float = float(spec.get("tail_seconds", 0.35))
	var waveform: String = str(spec.get("waveform", "sine"))
	var volume: float = float(spec.get("volume", 0.3))
	var data := PackedByteArray()
	for index in range(notes.size()):
		var hz: float = float(notes[index])
		var seconds: float = tail_seconds if index == notes.size() - 1 else note_seconds
		data.append_array(_render(hz, hz, seconds, waveform, volume))
	return _wav(data)


func _render(
	start_hz: float, end_hz: float, seconds: float, waveform: String, volume: float
) -> PackedByteArray:
	var frames: int = int(SAMPLE_RATE * seconds)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase: float = 0.0
	for i in range(frames):
		var t: float = float(i) / float(frames)
		var hz: float = lerpf(start_hz, end_hz, t)
		phase += TAU * hz / float(SAMPLE_RATE)
		# Fast attack, exponential decay: reads as a UI blip rather than a note.
		var envelope: float = minf(1.0, t * 40.0) * pow(1.0 - t, 2.2)
		var sample: float = _waveform_sample(waveform, phase, i) * envelope * volume
		var value: int = clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, value)
	return data


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream


func _waveform_sample(waveform: String, phase: float, index: int) -> float:
	match waveform:
		"square":
			return 1.0 if sin(phase) >= 0.0 else -1.0
		"noise":
			# Deterministic hash noise, mixed with the swept tone so a burn has
			# both a rush and a pitch to it.
			var noise: float = fmod(float(index) * 12.9898, 1.0) * 2.0 - 1.0
			return noise * 0.6 + sin(phase) * 0.4
		_:
			return sin(phase)
