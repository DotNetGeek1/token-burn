class_name ExpressionEvaluator
extends RefCounted

## Evaluates parameterised expressions and condition checks against run state.


func evaluate(expression: Variant, context: Dictionary = {}) -> Variant:
	if expression == null:
		return null
	if expression is bool or expression is int or expression is float:
		return expression
	if expression is String:
		var expr: String = expression
		if expr.begins_with("$"):
			var key: String = expr.substr(1)
			if context.has("parameters") and context["parameters"] is Dictionary:
				var params: Dictionary = context["parameters"]
				if params.has(key):
					return params[key]
			if context.has(key):
				return context[key]
			return null
		if expr.contains("."):
			return _resolve_path(expr, context)
		return expr
	return expression


func evaluate_condition(condition: Dictionary, context: Dictionary = {}) -> bool:
	var operator: String = str(condition.get("operator", "=="))
	if operator == "has_tag":
		var tag: String = str(evaluate(condition.get("right", ""), context))
		var tags: Array = _get_tags(context)
		return tag in tags
	var left: Variant = evaluate(condition.get("left", null), context)
	var right: Variant = evaluate(condition.get("right", null), context)
	if left == null or right == null:
		return false
	match operator:
		"<":
			return left < right
		"<=":
			return left <= right
		">":
			return left > right
		">=":
			return left >= right
		"==":
			return left == right
		"!=":
			return left != right
		"in":
			if right is Array:
				return left in right
			return false
		_:
			return false


func render_template(template: String, parameters: Dictionary) -> String:
	var result: String = template
	for key in parameters.keys():
		var value: Variant = parameters[key]
		# "+4 quality" rather than "+4.0 quality": a whole number written as a
		# float reads like a machine wrote the description.
		var display: String = (
			str(int(value))
			if value is float and is_equal_approx(float(value), roundf(float(value)))
			else str(value)
		)
		# No conversion happens here. A parameter is either a ratio the engine
		# multiplies by or a whole percent the card prints, and which one it is
		# has to be visible in the content: `convert: 0.45` alongside
		# `convert_pct: 45`. Guessing from the suffix meant a card could say
		# "0.45%" or "1500%" depending on how its author happened to write it.
		if key == "multiplier" and (value is float or value is int):
			display = str(value)
		result = result.replace("{%s}" % key, display)
	return result


func _resolve_path(path: String, context: Dictionary) -> Variant:
	var parts: PackedStringArray = path.split(".")
	if parts.is_empty():
		return null
	# A dispatch keeps its working values under their full dotted name
	# (`batch.known_bugs`, `stage.repeat_previous`), so the whole path is looked
	# up before it is treated as a path to walk. Without this, a condition on the
	# batch or the stage resolved to null and the subscription silently never
	# matched.
	if context.has("values") and context["values"] is Dictionary:
		var values: Dictionary = context["values"]
		if values.has(path):
			return values[path]
	if parts[0] == "job" and context.has("job"):
		var current: Variant = context["job"]
		for i in range(1, parts.size()):
			if current is Dictionary and current.has(parts[i]):
				current = current[parts[i]]
			else:
				return null
		return current
	if parts[0] == "values" and context.has("values"):
		return _walk(context["values"], parts, 1)
	if context.has("run_state") and context["run_state"] is Dictionary:
		return _walk(context["run_state"], parts, 0)
	return null


func _walk(current: Variant, parts: PackedStringArray, start_index: int) -> Variant:
	for i in range(start_index, parts.size()):
		if current is Dictionary and current.has(parts[i]):
			current = current[parts[i]]
		else:
			return null
	return current


func _get_tags(context: Dictionary) -> Array:
	if context.has("tags") and context["tags"] is Array:
		return context["tags"]
	if context.has("job") and context["job"] is Dictionary and context["job"].has("tags"):
		return context["job"]["tags"]
	return []
