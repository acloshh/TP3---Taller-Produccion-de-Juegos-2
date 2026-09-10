extends CharacterBody2D

const SPEED_COMBATE = 300.0
const SPEED_SIGILO = 100.0
const SPEED_ACOSTADO = 50.0
const SPEED_ARRASTRAR_REHEN = 40.0
const JUMP_VELOCITY = -700.0
var gravity_up = 1800.0
var gravity_down = 2200.0
const DISTANCIA_REHEN = 16

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

@export var flecha_escena: PackedScene

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
@onready var icono_flecha = $Interfaz/IconoFlecha 
@onready var texto_flecha = $Interfaz/TextoFlecha 
@onready var texto_melee = $Interfaz/TextoMelee
@onready var icono_cuchillo = $Interfaz/IconoCuchillo 
@onready var icono_puno = $"Interfaz/IconoPuño"
# @onready var icono_melee = $Interfaz/IconoMelee

# --- ESTADOS PRINCIPALES ---
var es_sigilo = false
var esta_acostado = false
var facing_left = false
var is_hanging = false 
var accion_bloqueante = false
var enemigo_agarrado = null 
var distancia_frente = 15.0

# --- SISTEMAS DE ARMAS Y COMBOS ---
var is_aiming = false
var fuerza_arco = 50.0 
var direccion_tiro = Vector2.RIGHT
var tipo_flecha = "letal" 
var arma_cuerpo_a_cuerpo = "cuchillo"
var combo_paso = 0
var ataque_encolado = false

func _ready():
	hitbox_shape.disabled = true
	popup_acciones.hide() 
	anim.animation_finished.connect(_on_animation_finished)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	
	icono_flecha.play(tipo_flecha)
	texto_flecha.text = "F. Letal"
	
	# Estado inicial de la interfaz melee
	texto_melee.text = "Cuchillo"
	icono_cuchillo.show()
	icono_puno.hide()

func _physics_process(delta):
	var should_disable_ledge = false
	if not is_hanging:
		should_disable_ledge = floor_check.is_colliding() or velocity.y < 0 or top_check.is_colliding()
	ledge_collider.disabled = should_disable_ledge

	check_ledge_grab()

	var direction = Input.get_axis("mover_izq", "mover_der")

	if Input.is_action_just_pressed("cambiar_postura") and not accion_bloqueante and enemigo_agarrado == null:
		es_sigilo = !es_sigilo

	esta_acostado = Input.is_action_pressed("abajo") and is_on_floor() and not accion_bloqueante

	if Input.is_action_just_pressed("atraer") and is_on_floor() and not accion_bloqueante:
		ejecutar_accion_bloqueante("atrae_en_posicion_de_sigilo" if es_sigilo else "atrae_en_posicion_de_combate")

	if Input.is_action_just_pressed("agarre") and not accion_bloqueante:
		if enemigo_agarrado == null:
			var cuerpos = area_takedown.get_overlapping_bodies()
			for cuerpo in cuerpos:
				if cuerpo.is_in_group("enemigo") and cuerpo.has_method("puede_recibir_takedown"):
					if cuerpo.puede_recibir_takedown(global_position.x):
						enemigo_agarrado = cuerpo
						enemigo_agarrado.ser_agarrado()
						popup_acciones.show()
						es_sigilo = false
						ejecutar_accion_bloqueante("agarra_enemigo")
						break 
		else:
			enemigo_agarrado.soltar_agarre()
			enemigo_agarrado = null
			popup_acciones.hide() 

	if Input.is_action_just_pressed("atacar") and not is_hanging:
		if enemigo_agarrado != null:
			enemigo_agarrado.ser_neutralizado()
			enemigo_agarrado = null
			popup_acciones.hide() 
			ejecutar_accion_bloqueante("mata_enemigo")
		elif not is_aiming:
			manejar_combo_ataque()

	if Input.is_action_pressed("apuntar") and not is_hanging and enemigo_agarrado == null and not accion_bloqueante:
		is_aiming = true
		
		if Input.is_action_pressed("disparar"):
			fuerza_arco += 600 * delta
			fuerza_arco = clamp(fuerza_arco, 50.0, 800.0)
		
		var vector_apuntado = Input.get_vector("mover_izq", "mover_der", "arriba", "abajo")
		if vector_apuntado != Vector2.ZERO:
			direccion_tiro = vector_apuntado.normalized()
			if direccion_tiro.x < 0:
				facing_left = true
			elif direccion_tiro.x > 0:
				facing_left = false
		else:
			direccion_tiro = Vector2(-1.0 if facing_left else 1.0, 0.0)
			
		actualizar_trayectoria(delta)
		
	elif Input.is_action_just_released("apuntar") and is_aiming:
		is_aiming = false
		linea_trayectoria.clear_points() 
		if fuerza_arco > 50.0:
			disparar_flecha()
		fuerza_arco = 50.0 

# --- ORIENTAR ÁREAS Y RAYOS ---

	if facing_left:
		hitbox.position.x = -distancia_frente
		area_takedown.position.x = -distancia_frente
		ledge_collider.position.x = -distancia_frente
		
		wall_check.position.x = 0
		wall_check.target_position.x = -distancia_frente
	else:
		hitbox.position.x = distancia_frente
		area_takedown.position.x = distancia_frente
		ledge_collider.position.x = distancia_frente
		
		wall_check.position.x = 0
		wall_check.target_position.x = distancia_frente

	if is_hanging:
		velocity = Vector2.ZERO 
		
		# Detecta si el jugador empuja el control hacia la pared que está agarrando
		var trepar_hacia_pared = (not facing_left and Input.is_action_just_pressed("mover_der")) or (facing_left and Input.is_action_just_pressed("mover_izq"))
		
		# Trepa si aprieta "arriba" O si empuja hacia la pared
		if Input.is_action_just_pressed("arriba") or trepar_hacia_pared:
			ejecutar_accion_bloqueante("trepa")
			velocity.y = JUMP_VELOCITY
			is_hanging = false
			
		# Se suelta si aprieta "abajo"
		elif Input.is_action_just_pressed("mover_izq"):
			is_hanging = false
				
	else:
		var esta_trepando = (accion_bloqueante and anim.animation == "trepa")
		
		if not is_aiming and not accion_bloqueante:
			if direction < 0:
				facing_left = false if enemigo_agarrado != null else true
			elif direction > 0:
				facing_left = true if enemigo_agarrado != null else false

		if not is_on_floor():
			# Aplica más peso si está cayendo que si está subiendo
			if velocity.y < 0:
				velocity.y += gravity_up * delta
			else:
				velocity.y += gravity_down * delta
		var current_speed = SPEED_COMBATE
		
		if accion_bloqueante or is_aiming:
			current_speed = 0.0 
			velocity.x = 0 
			if esta_trepando:
				velocity.y = -120 
		elif enemigo_agarrado != null:
			current_speed = SPEED_ARRASTRAR_REHEN
		elif esta_acostado:
			current_speed = SPEED_ACOSTADO
		elif es_sigilo:
			current_speed = SPEED_SIGILO

		if direction and not accion_bloqueante and not is_aiming:
			velocity.x = direction * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0, current_speed)

		# Salto (Botón A)
		if Input.is_action_just_pressed("saltar") and is_on_floor() and not accion_bloqueante and not esta_acostado:
			velocity.y = JUMP_VELOCITY
			es_sigilo = false # Saltar rompe el sigilo

		# Cortar el salto si el jugador suelta el botón rápido (Salto realista)
		if Input.is_action_just_released("saltar") and velocity.y < 0:
			velocity.y *= 0.5

	if enemigo_agarrado != null:
		var offset_x = -DISTANCIA_REHEN if facing_left else DISTANCIA_REHEN
		var offset_y = 10 
		enemigo_agarrado.global_position = global_position + Vector2(offset_x, offset_y)
		if enemigo_agarrado.has_node("AnimatedSprite2D"):
			enemigo_agarrado.get_node("AnimatedSprite2D").flip_h = facing_left

	update_animation(direction)
	move_and_slide()

	# --- CAMBIAR FLECHA (L1 / LB) ---
	if Input.is_action_just_pressed("cambiar_arma"):
		if tipo_flecha == "letal":
			tipo_flecha = "desmayante"
			texto_flecha.text = "F. Desmayante"
		else:
			tipo_flecha = "letal"
			texto_flecha.text = "F. Letal"
		icono_flecha.play(tipo_flecha)

# --- CAMBIAR ARMA CUERPO A CUERPO (R1 / RB) ---
	if Input.is_action_just_pressed("cambiar_melee"):
		if arma_cuerpo_a_cuerpo == "cuchillo":
			arma_cuerpo_a_cuerpo = "puño"
			texto_melee.text = "Puño"
			icono_cuchillo.hide()
			icono_puno.show()
		else:
			arma_cuerpo_a_cuerpo = "cuchillo"
			texto_melee.text = "Cuchillo"
			icono_cuchillo.show()
			icono_puno.hide()

func manejar_combo_ataque():
	if combo_paso == 0:
		combo_paso = 1
		ejecutar_accion_bloqueante("combo_" + arma_cuerpo_a_cuerpo + "_1")
		hitbox_shape.disabled = false
	elif combo_paso == 1 and accion_bloqueante:
		ataque_encolado = true 
	elif combo_paso == 2 and accion_bloqueante:
		ataque_encolado = true 

func ejecutar_accion_bloqueante(nombre_animacion):
	accion_bloqueante = true
	anim.play(nombre_animacion)

func actualizar_trayectoria(delta):
	linea_trayectoria.clear_points()
	var vel_simulada = direccion_tiro * fuerza_arco
	var pos_simulada = Vector2(5, 17.0) if not esta_acostado else Vector2(5, 22.0)
	linea_trayectoria.add_point(pos_simulada)
	
	var paso_tiempo = 0.05 
	for i in range(30):
		vel_simulada.y += gravity * paso_tiempo
		pos_simulada += vel_simulada * paso_tiempo
		linea_trayectoria.add_point(pos_simulada)

func disparar_flecha():
	if flecha_escena:
		var nueva_flecha = flecha_escena.instantiate()
		var offset_y = 10.0 if not esta_acostado else 15.0
		nueva_flecha.global_position = global_position + (direccion_tiro * 15.0) + Vector2(0, offset_y)
		nueva_flecha.velocity = direccion_tiro * fuerza_arco
		nueva_flecha.tipo = tipo_flecha
		get_parent().add_child(nueva_flecha)

func check_ledge_grab():
	if not is_hanging and not floor_check.is_colliding() and not accion_bloqueante:
		if wall_check.is_colliding() and is_on_floor():
			is_hanging = true

func update_animation(direction):
	anim.flip_h = facing_left
	
	if not is_hanging and anim.animation != "trepa":
		anim.offset.y = 0
		anim.offset.x = 0 
		
	if accion_bloqueante:
		return 
		
	if is_hanging:
		anim.offset.y = 5
		anim.offset.x = 3
		anim.play("trepa")
		anim.pause()
		anim.frame = 0
	elif is_aiming:
		anim.play("prepara_el_arco")
	elif enemigo_agarrado != null:
		if direction != 0:
			anim.play("camina_con_enemigo_agarrado") 
		else:
			anim.play("agarrar") 
	elif not is_on_floor():
		if velocity.y < 0:
			anim.play("salta_hacia_arriba")
		else:
			anim.play("cae")
	elif esta_acostado:
		if direction != 0:
			anim.play("arrastra_acostado")
		else:
			anim.play("idle_acostado")
	else:
		if direction != 0:
			if es_sigilo:
				anim.play("camina_sigilo")
			else:
				anim.play("camina_combate")
		else:
			if es_sigilo:
				anim.play("idle_sigilo")
			else:
				anim.play("idle_combate")

func _on_animation_finished():
	var terminada = anim.animation
	
	if "combo" in terminada or terminada == "mata_enemigo":
		hitbox_shape.disabled = true 
		
	if terminada == "trepa":
		var direccion = -1 if anim.flip_h else 1
		
		var empuje_x = 25 * direccion 
		var subida_y = 12 
		
		global_position += Vector2(empuje_x, subida_y)
		
		anim.offset.x = 0
		anim.offset.y = 0
		
		accion_bloqueante = false
		return
		
	if terminada == "combo_" + arma_cuerpo_a_cuerpo + "_1":
		if ataque_encolado:
			ataque_encolado = false
			combo_paso = 2
			ejecutar_accion_bloqueante("combo_" + arma_cuerpo_a_cuerpo + "_2")
			hitbox_shape.disabled = false
			return
	elif terminada == "combo_" + arma_cuerpo_a_cuerpo + "_2":
		if ataque_encolado:
			ataque_encolado = false
			combo_paso = 3
			ejecutar_accion_bloqueante("combo_" + arma_cuerpo_a_cuerpo + "_3")
			hitbox_shape.disabled = false
			return

	accion_bloqueante = false
	ataque_encolado = false
	combo_paso = 0

func _on_hitbox_body_entered(body):
	if body.is_in_group("enemigo"):
		if body.has_method("recibir_dano"):
			body.recibir_dano()
		else:
			body.queue_free()
