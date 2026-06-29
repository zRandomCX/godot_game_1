extends CanvasLayer

@onready var bar: TextureProgressBar = $Control/TextureProgressBar
@onready var anim: AnimationPlayer = $Control/AnimationPlayer

var max_health := 100
var health := 100


func _ready() -> void:
	add_to_group("hud")
	bar.max_value = max_health
	bar.value = health
	anim.play("beat")
	anim.speed_scale = 0.2


func update_health(new_health: int) -> void:
	health = clamp(new_health, 0, max_health)
	bar.value = health

	if health <= 0:
		player_died()
		return

	if health > 70:
		anim.speed_scale = 0.25
	elif health > 40:
		anim.speed_scale = 0.6
	elif health > 15:
		anim.speed_scale = 1.2
	else:
		anim.speed_scale = 2.2


func damage(amount: int) -> void:
	update_health(health - amount)


func player_died() -> void:
	anim.stop()
	anim.play("dead")
