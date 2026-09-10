extends Button

## Battle-local ownership of the engine clock. Turn/AP rules remain discrete.
const SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const CONFIG_PATH := "user://battle_speed.cfg"
var speed_index := 0
var _previous_scale := 1.0

func _ready() -> void:
	_previous_scale = Engine.time_scale
	_load_speed()
	pressed.connect(_cycle_speed)
	_apply_speed()

func _cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()
	_apply_speed()
	_save_speed()

func _apply_speed() -> void:
	Engine.time_scale = SPEEDS[speed_index]
	text = "▶ %d×" % int(SPEEDS[speed_index])
	tooltip_text = "战斗播放速度：%d 倍\n点击切换 1× / 2× / 4×（移动、演出和敌方行动等待）" % int(SPEEDS[speed_index])

func _load_speed() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	var saved := float(config.get_value("speed", "value", SPEEDS[speed_index]))
	var index := SPEEDS.find(saved)
	if index != -1:
		speed_index = index

func _save_speed() -> void:
	var config := ConfigFile.new()
	config.set_value("speed", "value", SPEEDS[speed_index])
	config.save(CONFIG_PATH)

func _exit_tree() -> void:
	# Do not leak battle speed into menus or subsequent scenes.
	Engine.time_scale = _previous_scale
