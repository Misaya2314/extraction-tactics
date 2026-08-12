@tool
class_name MapTileCatalog
extends Resource

@export var rules: Array[MapTileRule] = []


func find_rule(layer: MapTileRule.Layer, item_id: int) -> MapTileRule:
	for rule in rules:
		if rule.layer == layer and rule.item_id == item_id:
			return rule
	return null

