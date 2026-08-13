class_name EffectResolver
extends RefCounted

## Applies data-driven effects to run state with deterministic resolution order.

const MAX_TRACE_ENTRIES := 500

var _evaluator := ExpressionEvaluator.new()
var _trace: Array[Dictionary] = []
var _guard: ChainGuard = null


func clear_trace() -> void:
	_trace.clear()


func clear_guard() -> void:
	_guard = null


func get_trace() -> Array[Dictionary]:
	return _trace


func get_guard() -> ChainGuard:
	return _guard


func query_trace_for_target(target_path: String, chain_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in _trace:
		if str(entry.get("target", "")) != target_path:
			continue
		if chain_id != "" and str(entry.get("chain_id", "")) != chain_id:
			continue
		result.append(entry.duplicate(true))
	return result


func query_trace_breakdown(target_path: String, chain_id: String = "") -> Dictionary:
	var entries: Array[Dictionary] = query_trace_for_target(target_path, chain_id)
	var totals_by_operation: Dictionary = {}
	for entry in entries:
		var op: String = str(entry.get("operation", ""))
		if not totals_by_operation.has(op):
			totals_by_operation[op] = []
		totals_by_operation[op].append(entry.duplicate(true))
	return {
		"target": target_path,
		"chain_id": chain_id,
		"base_value": entries[0].get("before") if entries.size() > 0 else null,
		"final_value": entries[-1].get("after") if entries.size() > 0 else null,
		"entries": entries,
		"totals_by_operation": totals_by_operation,
	}


func begin_action(chain_id: String = "") -> void:
	_guard = ChainGuard.new(chain_id)


func dispatch(
	event_name: String,
	mod_ctx: ModifierContext,
	subscriptions: Array,
	chain_id: String = ""
) -> Array[Transaction]:
	if _guard == null:
		begin_action(chain_id)
	elif chain_id == "":
		chain_id = _guard.chain_id
	if not _guard.can_continue(event_name):
		if _guard.termination_reason != "":
			mod_ctx.messages.append(_guard.termination_reason)
		return []

	var eval_ctx: Dictionary = mod_ctx.to_eval_context()
	var matched: Array = []
	for sub in subscriptions:
		if str(sub.get("event", "")) != event_name:
			continue
		var conditions: Array = sub.get("conditions", [])
		var all_pass := true
		for condition in conditions:
			if condition is Dictionary and not _evaluator.evaluate_condition(condition, eval_ctx):
				all_pass = false
				break
		if all_pass:
			matched.append(sub)

	matched.sort_custom(func(a, b): return int(a.get("priority", 0)) < int(b.get("priority", 0)))

	var transactions: Array[Transaction] = []
	var by_phase: Dictionary = {}
	for sub in matched:
		var params: Dictionary = sub.get("parameters", {})
		if params.is_empty():
			params = {}
		else:
			params = params.duplicate(true)
		var source_id: String = str(sub.get("source_id", sub.get("id", "")))
		for effect in sub.get("effects", []):
			if not effect is Dictionary:
				continue
			var phase: int = EffectOps.phase_for_operation(str(effect.get("operation", "add")))
			if not by_phase.has(phase):
				by_phase[phase] = []
			by_phase[phase].append({
				"effect": effect,
				"sub": sub,
				"source_id": source_id,
				"parameters": params,
			})

	var phases: Array = [
		EffectOps.ResolutionPhase.BASE,
		EffectOps.ResolutionPhase.ADDITIVE,
		EffectOps.ResolutionPhase.MULTIPLICATIVE,
		EffectOps.ResolutionPhase.CONVERSION,
		EffectOps.ResolutionPhase.CAPS,
		EffectOps.ResolutionPhase.TRIGGERS,
		EffectOps.ResolutionPhase.FINALISE,
	]
	for phase in phases:
		if not by_phase.has(phase):
			continue
		for entry in by_phase[phase]:
			var effect: Dictionary = entry["effect"]
			var entry_eval_ctx: Dictionary = eval_ctx.duplicate(true)
			var entry_params: Dictionary = entry.get("parameters", {})
			entry_eval_ctx["parameters"] = entry_params
			mod_ctx.parameters = entry_params
			var tx := _apply_effect(
				mod_ctx,
				effect,
				entry_eval_ctx,
				event_name,
				chain_id,
				subscriptions,
				str(entry.get("source_id", "")),
				phase
			)
			if tx != null:
				transactions.append(tx)
				var effect_id: String = str(entry["sub"].get("source_id", entry["sub"].get("id", "")))
				_guard.record(event_name, effect_id)

	_finalize_to_run_state(mod_ctx)
	return transactions


func apply_effects(
	run_state: RunState,
	effects: Array,
	chain_id: String = "direct"
) -> void:
	var mod_ctx := ModifierContext.new("direct.apply", run_state)
	begin_action(chain_id)
	for effect in effects:
		if effect is EffectDefinition:
			_apply_effect_dict(mod_ctx, {
				"operation": effect.operation,
				"target": effect.target,
				"value": effect.value,
			}, mod_ctx.to_eval_context(), "direct.apply", chain_id, [])
		elif effect is Dictionary:
			_apply_effect_dict(mod_ctx, effect, mod_ctx.to_eval_context(), "direct.apply", chain_id, [])
	_finalize_to_run_state(mod_ctx)


func _apply_effect(
	mod_ctx: ModifierContext,
	effect: Dictionary,
	eval_ctx: Dictionary,
	event_name: String,
	chain_id: String,
	subscriptions: Array,
	source_id: String = "",
	phase: int = EffectOps.ResolutionPhase.BASE
) -> Transaction:
	return _apply_effect_dict(
		mod_ctx, effect, eval_ctx, event_name, chain_id, subscriptions, source_id, phase
	)


func _apply_effect_dict(
	mod_ctx: ModifierContext,
	effect: Dictionary,
	eval_ctx: Dictionary,
	event_name: String,
	chain_id: String,
	subscriptions: Array,
	source_id: String = "",
	phase: int = EffectOps.ResolutionPhase.BASE
) -> Transaction:
	var operation: String = str(effect.get("operation", "add")).to_lower()
	var target: String = str(effect.get("target", ""))
	# `business.demand` is derived from reputation and advertising every round,
	# so an effect adding to it directly would be wiped. Events and upgrades
	# mean it permanently; perks that mean it for one round target
	# `business.demand_modifier`, which is re-seeded from this base each round.
	if target == "business.demand" and operation == "add":
		target = "business.demand_modifier_base"
	var raw_value: Variant = effect.get("value", 0)
	var value: Variant = _resolve_effect_value(raw_value, eval_ctx)
	# "A share of another stat" rather than a literal figure. A perk worth a flat
	# £1,500 is a run-defining loan in the bedroom and a rounding error on the
	# moon; scaled against the rent or the fee, it means the same thing in both.
	if effect.has("value_from"):
		value = _as_float(
			mod_ctx.get_value(str(effect["value_from"]), 0.0)
		) * _as_float(value, 1.0)
	var current: Variant = mod_ctx.get_value(target, 0.0) if target != "" else null
	var result: Variant = current
	var metadata: Dictionary = {}

	if target == "compute.token_rate" and operation == "multiply" and mod_ctx.run_state != null:
		if event_name.begins_with("event.") or event_name == "direct.apply":
			mod_ctx.run_state.add_rate_modifier(_as_float(value, 1.0), 999, chain_id)
			metadata["rate_modifier"] = true
			metadata["multiplier"] = _as_float(value, 1.0)
			_record_trace(
				chain_id, event_name, target, operation, current, current, source_id, phase, metadata
			)
			return Transaction.new(chain_id, event_name, target, operation, current)

	match operation:
		"add":
			result = _as_float(current) + _as_float(value)
		"multiply":
			result = _as_float(current) * _as_float(value, 1.0)
		"set":
			result = value
		"cap_min":
			result = maxf(_as_float(current), _as_float(value))
		"cap_max":
			result = minf(_as_float(current), _as_float(value))
		"convert":
			result = _apply_convert(mod_ctx, effect, eval_ctx, target, value, metadata)
			if metadata.has("to"):
				target = str(metadata["to"])
		"copy":
			result = mod_ctx.get_value(str(value), current)
		"discount":
			# A discount takes a share off a cost. Applied to a value that is
			# already a credit it would shrink the credit instead, which is how
			# "stages run cooler" ended up making the pipeline's cooling modules
			# 40% worse at cooling.
			result = _as_float(current)
			if result > 0.0:
				result = result * (1.0 - _as_float(value))
		"defer_cost":
			result = _apply_defer_cost(mod_ctx, target, _as_float(value), effect, event_name, metadata)
		"borrow":
			result = _apply_borrow(mod_ctx, target, _as_float(value), current, metadata)
		"trigger":
			if mod_ctx.run_state != null and subscriptions.size() > 0:
				var trigger_event: String = str(value)
				if trigger_event != "" and _guard != null:
					_guard.push_depth()
					if _guard.can_continue(trigger_event):
						var trigger_ctx := ModifierContext.new(trigger_event, mod_ctx.run_state)
						trigger_ctx.job = mod_ctx.job.duplicate(true)
						trigger_ctx.values = mod_ctx.values.duplicate(true)
						trigger_ctx.parameters = mod_ctx.parameters.duplicate(true)
						trigger_ctx.rng = mod_ctx.rng
						dispatch(trigger_event, trigger_ctx, subscriptions, chain_id)
					_guard.pop_depth()
			result = current
		"spawn":
			result = _apply_spawn(mod_ctx, target, value, effect, eval_ctx, metadata)
		"remove":
			result = _apply_remove(mod_ctx, target, value, effect, eval_ctx, metadata)
		"reroll":
			result = _apply_reroll(mod_ctx, target, value, effect, eval_ctx, metadata)
		"repeat":
			result = _apply_repeat(
				mod_ctx, effect, eval_ctx, event_name, chain_id, subscriptions, source_id, phase
			)
		_:
			# A typo'd operation name silently doing nothing looks exactly like a
			# balance change that quietly never applied — authored content must
			# fail loudly here, not ship a perk or upgrade that does nothing.
			push_error("EffectResolver: unknown effect operation '%s' on target '%s'" % [operation, target])
			result = current

	if target != "" and operation not in ["spawn", "remove", "reroll", "repeat", "convert"]:
		mod_ctx.set_value(target, result)
	elif operation == "convert" and metadata.has("to"):
		pass
	elif operation in ["spawn", "remove", "reroll"] and target != "":
		mod_ctx.set_value(target, result)

	var tx := Transaction.new(chain_id, event_name, target, operation, result)
	_record_trace(chain_id, event_name, target, operation, current, result, source_id, phase, metadata)
	return tx


func _apply_convert(
	mod_ctx: ModifierContext,
	effect: Dictionary,
	eval_ctx: Dictionary,
	target: String,
	value: Variant,
	metadata: Dictionary
) -> Variant:
	var from_path: String = str(effect.get("from", ""))
	var to_path: String = target
	if to_path == "":
		to_path = str(effect.get("to", ""))
	var ratio: float = _as_float(value, 1.0)
	if effect.has("ratio"):
		ratio = _as_float(_evaluator.evaluate(effect.get("ratio"), eval_ctx), ratio)
	var consume: bool = bool(effect.get("consume", true))
	if from_path == "" or to_path == "":
		return mod_ctx.get_value(to_path, 0.0)
	var from_amount: float = _as_float(mod_ctx.get_value(from_path, 0.0))
	var transfer: float = from_amount * ratio
	var to_amount: float = _as_float(mod_ctx.get_value(to_path, 0.0)) + transfer
	mod_ctx.set_value(to_path, to_amount)
	if consume:
		mod_ctx.set_value(from_path, from_amount - transfer)
	metadata["from"] = from_path
	metadata["to"] = to_path
	metadata["ratio"] = ratio
	metadata["transfer"] = transfer
	metadata["consume"] = consume
	return to_amount


func _apply_defer_cost(
	mod_ctx: ModifierContext,
	target: String,
	amount: float,
	effect: Dictionary,
	event_name: String,
	metadata: Dictionary
) -> Variant:
	var prompts_until_due: int = int(effect.get("prompts", effect.get("due_in", 1)))
	if mod_ctx.run_state != null:
		var bills: Array = mod_ctx.run_state.economy.get("pending_bills", []).duplicate(true)
		bills.append({
			"amount": amount,
			"target": target,
			"prompts_until_due": prompts_until_due,
			"source_event": event_name,
		})
		mod_ctx.run_state.economy["pending_bills"] = bills
	metadata["deferred_amount"] = amount
	metadata["prompts_until_due"] = prompts_until_due
	return mod_ctx.get_value(target, 0.0)


func _apply_borrow(
	mod_ctx: ModifierContext,
	target: String,
	amount: float,
	current: Variant,
	metadata: Dictionary
) -> Variant:
	var result: float = _as_float(current) + amount
	if mod_ctx.run_state != null:
		EconomySystem.record_debt(mod_ctx.run_state, amount, "effect.borrow:%s" % target)
		metadata["debt_added"] = amount
	return result


func _apply_spawn(
	mod_ctx: ModifierContext,
	target: String,
	value: Variant,
	effect: Dictionary,
	eval_ctx: Dictionary,
	metadata: Dictionary
) -> Variant:
	var arr: Array = _get_array_at_path(mod_ctx, target)
	var spawn_count: int = 0
	if value is int or value is float:
		var count: int = maxi(0, int(value))
		var template: Variant = effect.get("template", {})
		if template is Dictionary:
			template = template.duplicate(true)
		else:
			template = {}
		if not _guard.can_spawn(count):
			metadata["blocked"] = true
			return arr
		for _i in range(count):
			var item: Variant = template
			if template is Dictionary:
				item = template.duplicate(true)
			arr.append(item)
			spawn_count += 1
	elif value != null:
		if not _guard.can_spawn(1):
			metadata["blocked"] = true
			return arr
		var payload: Variant = value
		if value is Dictionary:
			payload = _freeze_spawn_payload(value.duplicate(true), mod_ctx)
		arr.append(payload)
		spawn_count = 1
	if spawn_count > 0:
		_guard.record_spawn(spawn_count)
	metadata["spawned"] = spawn_count
	return arr


## Resolves `value_from` inside a spawned status payload so each spawn freezes
## its own numbers rather than re-reading live run state every tick.
func _freeze_spawn_payload(payload: Dictionary, mod_ctx: ModifierContext) -> Dictionary:
	if payload.has("subscriptions"):
		var frozen_subs: Array = []
		for sub in payload.get("subscriptions", []):
			if not sub is Dictionary:
				frozen_subs.append(sub)
				continue
			var copy: Dictionary = sub.duplicate(true)
			var effects: Array = []
			for effect in Array(copy.get("effects", [])):
				if not effect is Dictionary:
					effects.append(effect)
					continue
				var fx: Dictionary = effect.duplicate(true)
				if fx.has("value_from"):
					fx["value"] = _as_float(
						mod_ctx.get_value(str(fx["value_from"]), 0.0)
					) * _as_float(fx.get("value", 1.0), 1.0)
					fx.erase("value_from")
				effects.append(fx)
			copy["effects"] = effects
			frozen_subs.append(copy)
		payload["subscriptions"] = frozen_subs
	return payload


func _apply_remove(
	mod_ctx: ModifierContext,
	target: String,
	value: Variant,
	effect: Dictionary,
	eval_ctx: Dictionary,
	metadata: Dictionary
) -> Variant:
	var arr: Array = _get_array_at_path(mod_ctx, target)
	var removed: int = 0
	if value is int or value is float:
		var count: int = maxi(0, int(value))
		for _i in range(count):
			if arr.is_empty():
				break
			arr.pop_back()
			removed += 1
	else:
		var matcher: Variant = value
		var kept: Array = []
		for item in arr:
			if _item_matches(item, matcher):
				removed += 1
				continue
			kept.append(item)
		arr = kept
	metadata["removed"] = removed
	return arr


func _apply_reroll(
	mod_ctx: ModifierContext,
	target: String,
	value: Variant,
	effect: Dictionary,
	eval_ctx: Dictionary,
	metadata: Dictionary
) -> Variant:
	if mod_ctx.rng == null:
		metadata["skipped"] = "no_rng"
		return mod_ctx.get_value(target, null)
	var stream := mod_ctx.rng.derive("reroll.%s" % target.replace(".", "_"))
	if value is Dictionary:
		var spec: Dictionary = value
		if spec.has("pick") and spec["pick"] is Array:
			var picked: Variant = stream.pick(spec["pick"])
			metadata["picked"] = picked
			return picked
		var min_v: float = float(_evaluator.evaluate(spec.get("min", 0.0), eval_ctx))
		var max_v: float = float(_evaluator.evaluate(spec.get("max", 1.0), eval_ctx))
		var rolled: float = stream.next_range(min_v, max_v)
		metadata["min"] = min_v
		metadata["max"] = max_v
		return rolled
	if value is Array and value.size() > 0:
		var picked_item: Variant = stream.pick(value)
		metadata["picked"] = picked_item
		return picked_item
	var arr: Array = _get_array_at_path(mod_ctx, target)
	if arr.is_empty():
		return arr
	arr = stream.shuffle(arr)
	metadata["shuffled"] = true
	return arr


func _apply_repeat(
	mod_ctx: ModifierContext,
	effect: Dictionary,
	eval_ctx: Dictionary,
	event_name: String,
	chain_id: String,
	subscriptions: Array,
	source_id: String,
	phase: int
) -> Variant:
	var count: int = maxi(0, int(_evaluator.evaluate(effect.get("value", 1), eval_ctx)))
	if effect.has("max_repeats"):
		# Lets content compound off a growing number without compounding forever.
		count = mini(count, maxi(0, int(_evaluator.evaluate(effect.get("max_repeats"), eval_ctx))))
	var nested: Array = effect.get("effects", [])
	var repeat_target: String = str(effect.get("target", ""))
	if nested.is_empty():
		return mod_ctx.get_value(repeat_target, 0.0)
	for _i in range(count):
		for nested_effect in nested:
			if nested_effect is Dictionary:
				_apply_effect_dict(
					mod_ctx,
					nested_effect,
					eval_ctx,
					event_name,
					chain_id,
					subscriptions,
					source_id,
					phase
				)
	if repeat_target != "":
		return mod_ctx.get_value(repeat_target, 0.0)
	return count


func _get_array_at_path(mod_ctx: ModifierContext, path: String) -> Array:
	var current: Variant = mod_ctx.get_value(path, null)
	if current is Array:
		return current.duplicate(true)
	return []


func _set_array_at_path(mod_ctx: ModifierContext, path: String, arr: Array) -> void:
	mod_ctx.set_value(path, arr)


func _item_matches(item: Variant, matcher: Variant) -> bool:
	if matcher == null:
		return false
	if matcher is String:
		if item is Dictionary:
			return str(item.get("id", "")) == matcher
		return str(item) == matcher
	if matcher is Dictionary:
		if not item is Dictionary:
			return false
		for key in matcher.keys():
			if str(item.get(key)) != str(matcher[key]):
				return false
		return true
	return item == matcher


func _resolve_effect_value(raw: Variant, eval_ctx: Dictionary) -> Variant:
	var value: Variant = _evaluator.evaluate(raw, eval_ctx)
	if value != null:
		return value
	if raw is String and str(raw).begins_with("$"):
		push_warning("Unresolved effect parameter: %s" % raw)
		return 0.0
	if raw == null:
		return 0.0
	return raw


func _as_float(value: Variant, fallback: float = 0.0) -> float:
	if value == null:
		return fallback
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		TYPE_STRING:
			var text := str(value)
			if text.is_valid_float():
				return float(text)
			return fallback
		TYPE_BOOL:
			return 1.0 if value else 0.0
		_:
			return fallback


func _record_trace(
	chain_id: String,
	event_name: String,
	target: String,
	operation: String,
	before: Variant,
	after: Variant,
	source_id: String,
	phase: int,
	metadata: Dictionary = {}
) -> void:
	if _trace.size() >= MAX_TRACE_ENTRIES:
		_trace.pop_front()
	var entry: Dictionary = {
		"chain_id": chain_id,
		"event_name": event_name,
		"target": target,
		"operation": operation,
		"before": before,
		"after": after,
		"source_id": source_id,
		"phase": phase,
	}
	if not metadata.is_empty():
		entry["metadata"] = metadata.duplicate(true)
	_trace.append(entry)


## Stats that ComputeSystem derives from scratch on every recalculation. Any
## dispatch may read and modify them for the duration of that dispatch, but none
## may persist the result: a recalculation runs every round, and a stat that
## stored its own output would compound itself without limit. Content that means
## to change them for good targets the matching persistent stat, e.g.
## compute.efficiency_base.
const DERIVED_PATHS := [
	"compute.token_rate",
	"compute.efficiency",
	"compute.local_capacity",
	"compute.power_draw",
	## The two halves of the rate and the ratio between them, rebuilt from what
	## is racked and what is rented on every recalculation.
	"compute.local_rate",
	"compute.cloud_rate",
	"compute.cloud_share",
	## What the cloud shelf bills per prompt, re-seeded from
	## economy.cloud_base_cost_per_prompt. Persisting a discount here meant a
	## "50% off" perk halved its own last answer every recalculation, so £5,000
	## became £2,500, then £1,250, and eventually nothing.
	"economy.cloud_cost_per_prompt",
	## An upgrade's `+N cooling` is a description of the unit, not an instruction
	## to add N to the run. ComputeSystem sums it back out of what is installed,
	## which is what stops moving, reloading or recalculating counting it twice.
	"compute.cooling",
]


func _finalize_to_run_state(mod_ctx: ModifierContext) -> void:
	if mod_ctx.run_state == null:
		return
	var job_id: String = str(mod_ctx.job.get("id", ""))
	var active_jobs: Array = mod_ctx.run_state.business.get("active_jobs", [])
	for key in mod_ctx.values.keys():
		if key.begins_with("job."):
			var field: String = key.substr(4)
			if mod_ctx.job.size() > 0:
				mod_ctx.job[field] = mod_ctx.values[key]
			if job_id != "":
				for i in range(active_jobs.size()):
					var active_job: Dictionary = active_jobs[i]
					if str(active_job.get("id", "")) == job_id:
						active_job[field] = mod_ctx.values[key]
						active_jobs[i] = active_job
		elif key in DERIVED_PATHS:
			continue
		elif mod_ctx.run_state.get_value_at_path(key) != null:
			mod_ctx.run_state.set_value_at_path(key, mod_ctx.values[key])
		elif key.begins_with("build.") or key.begins_with("business."):
			mod_ctx.run_state.set_value_at_path(key, mod_ctx.values[key])
	if job_id != "":
		mod_ctx.run_state.business["active_jobs"] = active_jobs
		var single_active: Dictionary = mod_ctx.run_state.business.get("active_job", {})
		if str(single_active.get("id", "")) == job_id:
			mod_ctx.run_state.business["active_job"] = mod_ctx.job.duplicate(true)
		elif active_jobs.size() == 1 and str(active_jobs[0].get("id", "")) == job_id:
			mod_ctx.run_state.business["active_job"] = active_jobs[0].duplicate(true)
	elif mod_ctx.job.size() > 0 and active_jobs.size() == 1:
		mod_ctx.run_state.business["active_job"] = mod_ctx.job.duplicate(true)
