class_name AssetCatalogLoader
extends RefCounted

## Loads `presentation/asset_catalog.json`. AssetCatalog stays the public facade.


static func load_catalog(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("AssetCatalog: missing %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("AssetCatalog: could not open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
