extends CharacterBody2D

const SPEED_WALK = 100.0
const SPEED_RUN = 150.0
const SPEED_CROUCH = 60.0
const JUMP_VELOCITY = -300.0
const SPEED_ARRASTRAR = 40.0
const DISTANCIA_REHEN = 16

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

@export var flecha_escena: PackedScene # ARRASTRÁ TU FLECHA.TSCN ACÁ EN EL INSPECTOR

@onready var anim = $AnimatedSprite2D
@onready var ledge_collider = $LedgeCollider
@onready var wall_check = $WallCheck
@onready var floor_check = $FloorCheck
@onready var top_check = $TopCheck
@onready var hitbox = $Hitbox 
@onready var hitbox_shape = $Hitbox/CollisionShape2D 
@onready var area_takedown = $AreaTakedown
@onready var popup_acciones = $PopUpAcciones 
@onready var linea_trayectoria = $LineaTrayectoria
@onready var icono_flecha = $Interfaz/IconoFlecha # Asegurate de que la ruta coincida
@onready var texto_flecha = $Interfaz/TextoFlecha # Conectamos el Label

var is_crouching = false
var facing_left = false
var is_hanging = false 
var is_running = false 
var is_attacking = false 
var enemigo_agarrado = null 
var is_aiming = false

# --- NUEVAS VARIABLES DE ARCO ---
var fuerza_arco = 50.0 
var direccion_tiro = Vector2.RIGHT
var tipo_flecha = "letal" # Puede ser "letal" o "desmayante"

func _ready():
	hitbox_shape.disabled = true
	popup_acciones.hide() 
	anim.animation_finished.connect(_on_animation_finished)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	
	# Seteamos la interfaz inicial
	icono_flecha.play(tipo_flecha)
	texto_flecha.text = "F. Letal" # O "Flecha Letal", lo que entre mejor en tu UI

func _physics_process(delta):
	var should_disable_ledge = is_on_floor() or velocity.y < 0 or (top_check.is_colliding() and not is_hanging)
	ledge_collider.disabled = should_disable_ledge

	check_ledge_grab()

	var direction = Input.get_axis("ui_left", "ui_right")

	# --- LÓGICA DE AGARRAR / DESMAYAR (L1) ---
	if Input.is_action_just_pressed("agarrar"):
		if enemigo_agarrado == null:
			var cuerpos = area_takedown.get_overlapping_bodies()
			for cuerpo in cuerpos:
				if cuerpo.is_in_group("enemigo") and cuerpo.has_method("puede_recibir_takedown"):
					if cuerpo.puede_recibir_takedown(global_position.x):
						enemigo_agarrado = cuerpo
						enemigo_agarrado.ser_agarrado()
						popup_acciones.show() 
						break 
		else:
			enemigo_agarrado.soltar_agarre()
			enemigo_agarrado = null
			popup_acciones.hide() 

	# --- LÓGICA DE ATAQUE CUERPO A CUERPO (Cuadrado / 🟥) ---
	if Input.is_action_just_pressed("atacar") and not is_attacking and not is_hanging:
		if enemigo_agarrado != null:
			enemigo_agarrado.ser_neutralizado()
			enemigo_agarrado = null
			popup_acciones.hide() 
			is_attacking = true
		else:
			is_attacking = true
			hitbox_shape.disabled = false 

	# --- LÓGICA DE APUNTAR Y DISPARAR ARCO ---
# --- LÓGICA DE APUNTAR Y DISPARAR ARCO ---
	if Input.is_action_pressed("disparar") and not is_hanging and enemigo_agarrado == null:
		is_aiming = true
		
		# 1. Tensión automática (sube sola mientras mantengas apretado)
		fuerza_arco += 600 * delta # Sube rapidísimo
		fuerza_arco = clamp(fuerza_arco, 50.0, 800.0)
		
		# 2. Apuntado libre con el analógico o flechas
		var vector_apuntado = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		
		if vector_apuntado != Vector2.ZERO:
			# Apunta hacia donde estés moviendo la palanca
			direccion_tiro = vector_apuntado.normalized()
			
			# Hacemos que el personaje se dé vuelta si apuntás para atrás
			if direccion_tiro.x < 0:
				facing_left = true
			elif direccion_tiro.x > 0:
				facing_left = false
		else:
			# Si no tocás la palanca, apunta recto hacia adelante por defecto
			direccion_tiro = Vector2(-1.0 if facing_left else 1.0, 0.0)
			
		actualizar_trayectoria(delta)
		
	elif Input.is_action_just_released("disparar") and is_aiming:
		is_aiming = false
		linea_trayectoria.clear_points() 
		disparar_flecha()
		fuerza_arco = 50.0 # Reseteamos la fuerza al disparar

	# Orientar las áreas 
	if facing_left:
		hitbox.position.x = -abs(hitbox.position.x)
		area_takedown.position.x = -abs(area_takedown.position.x)
	else:
		hitbox.position.x = abs(hitbox.position.x)
		area_takedown.position.x = abs(area_takedown.position.x)

	if is_hanging:
		velocity = Vector2.ZERO 
		
		if wall_check.is_colliding():
			var normal = wall_check.get_collision_normal(0)
			facing_left = normal.x > 0
		
		if Input.is_action_just_pressed("ui_up"):
			velocity.y = JUMP_VELOCITY
			is_hanging = false
		elif Input.is_action_just_pressed("ui_down"):
			is_hanging = false
			
	else:
		# BLOQUEO DEL GIRO: Si estamos apuntando, el personaje NO debe darse vuelta mágicamente
		if not is_aiming:
			if direction < 0:
				if enemigo_agarrado != null:
					facing_left = false 
				else:
					facing_left = true
			elif direction > 0:
				if enemigo_agarrado != null:
					facing_left = true 
				else:
					facing_left = false

		if not is_on_floor():
			velocity.y += gravity * delta

		var current_speed = SPEED_WALK
		
		if is_aiming:
			current_speed = 0.0 
			is_running = false
			velocity.x = 0 # ¡ESTE ES EL FRENO EN SECO QUE ARREGLA EL BUG!
		elif enemigo_agarrado != null:
			current_speed = SPEED_ARRASTRAR	
		else:
			if is_on_floor():
				is_crouching = Input.is_action_pressed("ui_down")
				is_running = Input.is_action_pressed("correr")

			if Input.is_action_just_pressed("ui_up") and is_on_floor() and not is_crouching:
				velocity.y = JUMP_VELOCITY

			if is_crouching:
				current_speed = SPEED_CROUCH
			elif is_running:
				current_speed = SPEED_RUN

		if direction and not is_attacking and not is_aiming:
			velocity.x = direction * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed)

	# --- ARRASTRAR AL ENEMIGO ---
	if enemigo_agarrado != null:
		var offset_x = -DISTANCIA_REHEN if facing_left else DISTANCIA_REHEN
		var offset_y = 10 
		
		enemigo_agarrado.global_position = global_position + Vector2(offset_x, offset_y)
		if enemigo_agarrado.has_node("AnimatedSprite2D"):
			enemigo_agarrado.get_node("AnimatedSprite2D").flip_h = facing_left

	update_animation(direction)
	move_and_slide()


# --- LÓGICA DE CAMBIAR FLECHA ---
	if Input.is_action_just_pressed("cambiar_flecha"):
		if tipo_flecha == "letal":
			tipo_flecha = "desmayante"
			texto_flecha.text = "F. Desmayante"
		else:
			tipo_flecha = "letal"
			texto_flecha.text = "F. Letal"
			
		# Cambiamos la imagen de la cajita en la interfaz
		icono_flecha.play(tipo_flecha)
# --- NUEVAS FUNCIONES DE ARCO --

func actualizar_trayectoria(delta):
	linea_trayectoria.clear_points()
	
	var vel_simulada = direccion_tiro * fuerza_arco
	
	# El punto inicial de la línea
	# Le sacamos el menos al 5 para bajar la línea al brazo. 
	# Si está agachado, la bajamos un poco más (a 10).
	var pos_simulada = Vector2(5, 17.0) if not is_crouching else Vector2(5, 22.0)
	linea_trayectoria.add_point(pos_simulada)
	
	var paso_tiempo = 0.05 
	for i in range(30):
		vel_simulada.y += gravity * paso_tiempo
		pos_simulada += vel_simulada * paso_tiempo
		linea_trayectoria.add_point(pos_simulada)

func disparar_flecha():
	# Le pasamos la velocidad y el tipo
	if flecha_escena:
		var nueva_flecha = flecha_escena.instantiate()
		
		# Disparamos usando la fuerza acumulada y la dirección
		nueva_flecha.velocity = direccion_tiro * fuerza_arco
		
		# Hacemos lo mismo con la flecha física
		var offset_y = 10.0 if not is_crouching else 15.0
		nueva_flecha.global_position = global_position + (direccion_tiro * 15.0) + Vector2(0, offset_y)
		# Le pasamos la velocidad y el tipo
		nueva_flecha.velocity = direccion_tiro * fuerza_arco
		nueva_flecha.tipo = tipo_flecha
		get_parent().add_child(nueva_flecha)

func check_ledge_grab():
	if not is_hanging and not floor_check.is_colliding():
		if wall_check.is_colliding() and velocity.y == 0 and not is_on_floor():
			is_hanging = true

func update_animation(direction):
	anim.flip_h = facing_left
	
	if is_attacking:
		anim.play("acuchillar")
	elif is_hanging:
		anim.play("trepar")
		anim.pause()
		anim.frame = 0
	elif enemigo_agarrado != null:
		if direction != 0:
			anim.play("caminar_agarrando") 
		else:
			anim.play("agarrar") 
	elif not is_on_floor():
		anim.play("saltar")
	elif is_crouching:
		if direction != 0:
			anim.play("caminar_agachado")
		else:
			anim.play("agacharse_idle")
	else:
		if direction != 0 and not is_aiming:
			if is_running:
				anim.play("correr")
			else:
				anim.play("caminar") 
		else:
			anim.play("idle")

func _on_animation_finished():
	if anim.animation == "acuchillar":
		is_attacking = false
		hitbox_shape.disabled = true 

func _on_hitbox_body_entered(body):
	if body.is_in_group("enemigo"):
		if body.has_method("recibir_dano"):
			body.recibir_dano()
		else:
			body.queue_free()
