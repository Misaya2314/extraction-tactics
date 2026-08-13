@tool
class_name LootTableDefinition
extends Resource

@export var table_id: StringName = &""
@export var fixed_items: Array[ItemDefinition] = []
@export var random_pool: Array[ItemDefinition] = []
@export_range(0, 99, 1) var random_draw_count: int = 0
@export var allow_duplicates: bool = false


func is_valid() -> bool:
	if table_id == &"" or random_draw_count < 0:
		return false
	if random_draw_count > 0 and random_pool.is_empty():
		return false
	if not allow_duplicates and random_draw_count > random_pool.size():
		return false
	for item in fixed_items:
		if item == null or not item.is_valid():
			return false
	for item in random_pool:
		if item == null or not item.is_valid():
			return false
	return true


func validate() -> bool:
	return is_valid()


func generate_contents(random_seed: int = -1, rng: RandomNumberGenerator = null) -> Array[ItemDefinition]:
	var result: Array[ItemDefinition] = []
	if not is_valid():
		return result

	for item in fixed_items:
		result.append(item)
	if random_draw_count == 0:
		return result

	var generator: RandomNumberGenerator = rng
	if generator == null:
		generator = RandomNumberGenerator.new()
		if random_seed != -1:
			generator.seed = random_seed
		else:
			generator.randomize()

	var candidates: Array[ItemDefinition] = []
	for item in random_pool:
		candidates.append(item)
	for _draw in range(random_draw_count):
		var index: int = generator.randi_range(0, candidates.size() - 1)
		result.append(candidates[index])
		if not allow_duplicates:
			candidates.remove_at(index)
	return result


func roll(random_seed: int = -1, rng: RandomNumberGenerator = null) -> Array[ItemDefinition]:
	return generate_contents(random_seed, rng)
