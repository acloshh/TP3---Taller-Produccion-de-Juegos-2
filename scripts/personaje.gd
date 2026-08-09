extends CharacterBody2D

const SPEED_RUN = 150.0
const SPEED_CROUCH = 60.0
const JUMP_VELOCITY = -300.0

# Obtenemos la gravedad de la configuración del proyecto
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var anim = $AnimatedSprite2D

var is_crouching = false
var facing_left = false

func _physics_process(delta):
	# Aplicar gravedad
	if not is_on_floor():
		velocity.y += gravity * delta

	# Lógica para agacharse (solo si estamos en el suelo)
	if is_on_floor():
		if Input.is_action_pressed("ui_down"):
			is_crouching = true
		else:
			is_crouching = false

	# Lógica de salto (bloqueada si el personaje está agachado)
	if Input.is_action_just_pressed("ui_up") and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY

	# Obtener dirección de movimiento (-1, 0, 1)
	var direction = Input.get_axis("ui_left", "ui_right")
	
	# Actualizar hacia dónde mira el personaje
	if direction < 0:
		facing_left = true
	elif direction > 0:
		facing_left = false

	# Ajustar la velocidad dependiendo de si está agachado o de pie
	var current_speed = SPEED_CROUCH if is_crouching else SPEED_RUN

	# Aplicar velocidad horizontal
	if direction:
		velocity.x = direction * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)

	update_animation(direction)
	move_and_slide()

func update_animation(direction):
	# Determinamos el sufijo basado en hacia dónde mira
	var suffix = "_izq" if facing_left else ""
	
	if not is_on_floor():
		if velocity.y < 0:
			anim.play("saltar" + suffix)
		else:
			anim.play("caida_salto" + suffix)
	elif is_crouching:
		if direction != 0:
			anim.play("caminar_agachado" + suffix)
		else:
			anim.play("agacharse_idle" + suffix)
	else:
		if direction != 0:
			anim.play("correr" + suffix)
		else:
			anim.play("idle" + suffix)
