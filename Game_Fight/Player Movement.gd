extends CharacterBody2D

const SPEED := 60.0
const BLOCK_SPEED := 20.0
const JUMP_VELOCITY := 0.0
const ROLL_SPEED := 80.0
const ROLL_DURATION := 0.25

# Estamina
const STAMINA_MAX := 100.0
const STAMINA_REGEN := 15.0       # Por segundo
const STAMINA_ATTACK_COST := 25.0 # Costo por golpe
const STAMINA_LOW := 20.0         # Umbral de estamina baja (golpe lento)

# Escudo
const SHIELD_MAX := 50.0
const SHIELD_REGEN := 5.0         # Por segundo (se regenera lento fuera de bloqueo)

var stamina := STAMINA_MAX
var shield := SHIELD_MAX
var shield_broken := false        # Si el escudo llega a 0, se rompe temporalmente

var attacking := false
var dead := false
var rolling := false
var blocking := false
var roll_direction := 0
var roll_requested := false
var roll_time_left := 0.0
var facing := 1

var max_health := 100
var health := 100

@onready var animationPlayer: AnimationPlayer = $AnimationPlayer
@onready var hitbox: Area2D = $Area2D


func _ready() -> void:
	add_to_group("player")
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_health"):
		hud.update_health(health)
	if hud and hud.has_method("update_stamina"):
		hud.update_stamina(stamina, STAMINA_MAX)
	if hud and hud.has_method("update_shield"):
		hud.update_shield(shield, SHIELD_MAX)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		roll_requested = true

	if event is InputEventKey and not event.echo and event.keycode == KEY_B:
		if event.pressed and not dead and not attacking and not rolling and not shield_broken:
			blocking = true
		elif not event.pressed:
			blocking = false


func attack() -> void:
	var areas = hitbox.get_overlapping_areas()
	var bodies = hitbox.get_overlapping_bodies()

	for a in areas:
		var parent = a.get_parent()
		if parent == self:
			continue
		if parent.is_in_group("enemy") and parent.has_method("take_damage"):
			parent.take_damage(10)

	for body in bodies:
		if body == self:
			continue
		if body.is_in_group("enemy") and body.has_method("take_damage"):
			body.take_damage(10)


func take_damage(amount: int) -> void:
	if dead:
		return

	# Si está bloqueando, el daño va al escudo primero
	if blocking and not shield_broken:
		shield -= amount
		if shield <= 0:
			shield = 0
			shield_broken = true
			blocking = false  # Se rompe el bloqueo
			# Regenerar escudo tras 3 segundos
			get_tree().create_timer(3.0).timeout.connect(_regen_shield)
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("update_shield"):
			hud.update_shield(shield, SHIELD_MAX)
		return

	# Sin bloqueo o escudo roto → daño a la vida
	if attacking:
		return

	health = max(health - amount, 0)

	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_health"):
		hud.update_health(health)

	if health <= 0:
		die()


func _regen_shield() -> void:
	shield_broken = false
	# Empieza a regenerar desde 0


func die() -> void:
	if dead:
		return
	dead = true
	attacking = false
	rolling = false
	blocking = false
	roll_direction = 0
	roll_requested = false
	roll_time_left = 0.0
	velocity = Vector2.ZERO
	animationPlayer.play("Dead_P")

	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("player_died"):
		hud.player_died()


func start_ragdoll() -> void:
	if dead or attacking or rolling or blocking:
		return
	if not is_on_floor():
		return

	rolling = true
	roll_time_left = ROLL_DURATION
	velocity = Vector2.ZERO
	roll_direction = 0

	if Input.is_action_pressed("ui_left"):
		roll_direction = -1
		facing = -1
		if animationPlayer.has_animation("RagdollLeft"):
			animationPlayer.play("RagdollLeft")
	elif Input.is_action_pressed("ui_right"):
		roll_direction = 1
		facing = 1
		if animationPlayer.has_animation("RagdollRight"):
			animationPlayer.play("RagdollRight")
	else:
		roll_direction = 0
		if facing < 0:
			if animationPlayer.has_animation("RagdollLeft"):
				animationPlayer.play("RagdollLeft")
		else:
			if animationPlayer.has_animation("RagdollRight"):
				animationPlayer.play("RagdollRight")


func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_update_stamina(delta)
	_update_shield_regen(delta)

	if blocking:
		if not is_on_floor():
			velocity += get_gravity() * delta
		var direction := Input.get_axis("ui_left", "ui_right")
		if direction != 0:
			velocity.x = direction * BLOCK_SPEED
			facing = -1 if direction < 0 else 1
		else:
			velocity.x = move_toward(velocity.x, 0.0, BLOCK_SPEED)
		move_and_slide()
		animations(direction)
		return

	if roll_requested:
		roll_requested = false
		start_ragdoll()

	if rolling:
		roll_time_left -= delta
		if roll_direction == -1:
			velocity.x = -ROLL_SPEED
		elif roll_direction == 1:
			velocity.x = ROLL_SPEED
		else:
			velocity.x = 0.0
		velocity.y = 0.0
		move_and_slide()
		if roll_time_left <= 0.0:
			rolling = false
			roll_direction = 0
			velocity = Vector2.ZERO
			if not dead:
				animationPlayer.play("Idle")
		return

	if attacking:
		move_and_slide()
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("attack"):
		_try_attack()
		return

	var direction := Input.get_axis("ui_left", "ui_right")
	if direction != 0:
		velocity.x = direction * SPEED
		facing = -1 if direction < 0 else 1
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)

	move_and_slide()
	animations(direction)


func _try_attack() -> void:
	# Sin estamina suficiente → ataque más lento (solo si hay algo de estamina)
	if stamina <= 0:
		return  # No puede atacar sin nada de estamina

	attacking = true
	velocity.x = 0.0

	if stamina < STAMINA_LOW:
		# Ataque lento: la animación va a la mitad de velocidad
		animationPlayer.speed_scale = 0.5
	else:
		animationPlayer.speed_scale = 1.0

	animationPlayer.play("Attack")
	attack()

	# Consumir estamina
	stamina = max(stamina - STAMINA_ATTACK_COST, 0)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("update_stamina"):
		hud.update_stamina(stamina, STAMINA_MAX)


func _update_stamina(delta: float) -> void:
	# Regenerar estamina cuando no está atacando
	if not attacking and stamina < STAMINA_MAX:
		stamina = min(stamina + STAMINA_REGEN * delta, STAMINA_MAX)
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("update_stamina"):
			hud.update_stamina(stamina, STAMINA_MAX)


func _update_shield_regen(delta: float) -> void:
	# Regenerar escudo lentamente cuando no está bloqueando y no está roto
	if not blocking and not shield_broken and shield < SHIELD_MAX:
		shield = min(shield + SHIELD_REGEN * delta, SHIELD_MAX)
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("update_shield"):
			hud.update_shield(shield, SHIELD_MAX)


func animations(direction: float) -> void:
	if dead or rolling:
		return
	if is_on_floor():
		if direction == 0:
			animationPlayer.play("Idle")
		else:
			animationPlayer.play("Run")


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Attack":
		attacking = false
		animationPlayer.speed_scale = 1.0  # Restaurar velocidad normal
	elif anim_name == "RagdollLeft" or anim_name == "RagdollRight":
		if rolling:
			rolling = false
			roll_direction = 0
			velocity = Vector2.ZERO
			if not dead:
				animationPlayer.play("Idle")


func _on_area_2d_body_entered(_body: Node) -> void:
	pass
