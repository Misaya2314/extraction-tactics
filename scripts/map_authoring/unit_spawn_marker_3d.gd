@tool
class_name UnitSpawnMarker3D
extends MapMarker3D

@export var unit_name: StringName = &"Unit"
@export_enum("player", "enemy") var faction: String = "player"
@export var facing: Vector2i = Vector2i.DOWN
@export var visual_color: Color = Color("4f9dff")
@export var patrol_route_id: StringName = &""
@export var archetype: UnitArchetype
@export var weapon: WeaponDefinition
@export var encounter_id: StringName = &""


func to_data() -> MapSpawnData:
	var data := MapSpawnData.new()
	data.unit_name = unit_name
	data.faction = StringName(faction)
	data.cell = cell
	data.facing = facing
	data.visual_color = visual_color
	data.patrol_route_id = patrol_route_id
	data.archetype = archetype
	data.weapon = weapon
	data.encounter_id = encounter_id
	return data
