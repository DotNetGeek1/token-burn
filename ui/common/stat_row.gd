class_name StatRow
extends HBoxContainer

func setup(label_text: String, value_text: String, stat_key: String = "") -> void:
	$NameLabel.text = label_text
	$ValueLabel.text = value_text
	if stat_key != "":
		var tex: Texture2D = AssetCatalog.stat_icon(stat_key)
		if tex == null:
			tex = AssetCatalog.category_icon(stat_key)
		$Icon.texture = tex
		$Icon.visible = tex != null
	else:
		$Icon.visible = false
