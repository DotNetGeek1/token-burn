class_name DeterministicRng
extends RefCounted

## Seeded xorshift64* PRNG with named substreams for reproducible simulation.

const _MULTIPLIER: int = 6364136223846793005
const _DEFAULT_SEED: int = 0xDEADBEEF
const _MASK: int = 0x7FFFFFFFFFFFFFFF

var _seed: int = _DEFAULT_SEED
var _state: int = _DEFAULT_SEED
var _derived: Dictionary = {}
var _stream_counter: int = 0


func _init(initial_seed: int = 0) -> void:
	set_seed(initial_seed if initial_seed != 0 else _DEFAULT_SEED)


func set_seed(initial_seed: int) -> void:
	_seed = absi(initial_seed) & _MASK
	_state = _seed if _seed != 0 else 1
	_derived.clear()
	_stream_counter = 0


func get_seed() -> int:
	return _seed


func derive(stream_name: String) -> DeterministicRng:
	if _derived.has(stream_name):
		return _derived[stream_name]
	var child := DeterministicRng.new()
	var hash_seed: int = absi(int(hash(str(_seed) + stream_name))) & _MASK
	if hash_seed == 0:
		hash_seed = 1
	child.set_seed(hash_seed)
	_derived[stream_name] = child
	return child


func next_stream() -> DeterministicRng:
	_stream_counter += 1
	return derive("stream_%d" % _stream_counter)


func next_u64() -> int:
	var x: int = _state & _MASK
	x = (x ^ (x >> 12)) & _MASK
	x = (x ^ (x << 25)) & _MASK
	x = (x ^ (x >> 27)) & _MASK
	_state = x
	return (x * _MULTIPLIER) & _MASK


func next_int() -> int:
	return next_u64() & _MASK


func next_float() -> float:
	return float(next_u64() & 0xFFFFFFFF) / 4294967296.0


func next_range(min_value: float, max_value: float) -> float:
	return lerpf(min_value, max_value, next_float())


func next_int_range(min_value: int, max_value: int) -> int:
	if max_value <= min_value:
		return min_value
	return min_value + (next_int() % (max_value - min_value + 1))


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[next_int() % items.size()]


func shuffle(items: Array) -> Array:
	var result: Array = items.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j: int = next_int() % (i + 1)
		var tmp = result[i]
		result[i] = result[j]
		result[j] = tmp
	return result


func weighted_pick(items: Array, weight_key: String = "weight") -> Variant:
	if items.is_empty():
		return null
	var total: float = 0.0
	for item in items:
		if item is Dictionary:
			total += float(item.get(weight_key, 1.0))
		elif item is Resource:
			total += float(item.get(weight_key) if item.get(weight_key) != null else 1.0)
		else:
			total += 1.0
	if total <= 0.0:
		return pick(items)
	var roll: float = next_float() * total
	var cumulative: float = 0.0
	for item in items:
		var w: float = 1.0
		if item is Dictionary:
			w = float(item.get(weight_key, 1.0))
		elif item is Resource and item.get(weight_key) != null:
			w = float(item.get(weight_key))
		cumulative += w
		if roll <= cumulative:
			return item
	return items[-1]
