extends CharacterBody2D

var max_health := 100
var health := 100
var player_inside: Node = null
var player_ref: Node = null

var damage_cooldown := 0.0
const DAMAGE_INTERVAL := 1.5
const FOLLOW_SPEED := 40.0
const ATTACK_RANGE := 60.0

@onready var area: Area2D = $Area2D


func _ready() -> void:
	add_to_group("enemy")

	if not area.body_entered.is_connected(_on_area_2d_body_entered):
		area.body_entered.connect(_on_area_2d_body_entered)
	if not area.body_exited.is_connected(_on_area_2d_body_exited):
		area.body_exited.connect(_on_area_2d_body_exited)

	# Buscar al jugador en la escena para poder seguirlo
	await get_tree().process_frame
	player_ref = get_tree().get_first_node_in_group("player")


func _physics_process(delta: float) -> void:
	# Cooldown de daño
	if damage_cooldown > 0.0:
		damage_cooldown -= delta

	# Seguir al jugador siempre que exista y no esté muerto
	if player_ref != null and is_instance_valid(player_ref):
		if player_ref.get("dead") != true:
			_follow_player(delta)

	# Aplicar gravedad
	if not is_on_floor():
		velocity += get_gravity() * delta

	move_and_slide()

	# Hacer daño si el jugador está dentro del área y el cooldown terminó
	if player_inside != null and damage_cooldown <= 0.0:
		_deal_damage_to_player()


func _follow_player(delta: float) -> void:
	var distance = global_position.distance_to(player_ref.global_position)

	if distance > ATTACK_RANGE:
		# Moverse hacia el jugador
		var direction = (player_ref.global_position - global_position).normalized()
		velocity.x = direction.x * FOLLOW_SPEED
	else:
		# Está en rango, detenerse
		velocity.x = move_toward(velocity.x, 0.0, FOLLOW_SPEED)


func _deal_damage_to_player() -> void:
	if player_inside == null:
		return
	if not player_inside.has_method("take_damage"):
		return
	if player_inside.get("dead") == true:
		return
	if player_inside.get("blocking") == true:
		return
	if player_inside.get("attacking") == true:
		return

	player_inside.take_damage(10)
	damage_cooldown = DAMAGE_INTERVAL


func take_damage(amount: int) -> void:
	health -= amount
	print("Enemigo recibió daño:", amount, "| Vida restante:", health)
	if health <= 0:
		queue_free()


func _on_area_2d_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		print("Jugador entró al área del enemigo")
		player_inside = body
		damage_cooldown = 1.0  # 1 segundo antes del primer golpe


func _on_area_2d_body_exited(body: Node) -> void:
	if body == player_inside:
		print("Jugador salió del área del enemigo")
		player_inside = null
		damage_cooldown = 0.0
