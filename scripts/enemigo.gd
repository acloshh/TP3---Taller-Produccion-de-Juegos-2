extends CharacterBody2D

enum Estado { PATRULLANDO, SOSPECHANDO, AGRESIVO, MUERTO, AGARRADO, DESMAYADO, LEVANTANDOSE, ESPERANDO_MARCADOR, SALTANDO, TREPANDO, CAYENDO_POR_AGUJERO, EN_ESCALERA }

var timer_marcador = 0.0
var orden_pendiente = 0
var estado_actual = Estado.PATRULLANDO

const SPEED_PATRULLA = 100.0
const SPEED_SOSPECHA = 150
const SPEED_PERSECUCION = 285.0

# --- FÍSICAS PROPORCIONALES AL JUGADOR ---
const JUMP_VELOCITY = -650.0 
var gravity_up = 1800.0
var gravity_down = 2200.0

# --- VARIABLES DE ESCALERA ---
const SPEED_ESCALERA = 60.0
var direccion_escalera = -1

@onready var anim = $AnimatedSprite2D
@onready var ray_muro = $RayMuro
@onready var ray_piso = $RayPiso
@onready var ray_vision = $RayVision

@onready var wall_check = $WallCheck
@onready var floor_check = $FloorCheck

var direccion_x = 1
var tiempo_sospecha = 0.0
var tiempo_desmayado = 0.0 

var vida = 3
var esta_herido = false
var tiene_gorro = true
var compensacion_sprite = 0.0

func _ready():
	anim.animation_finished.connect(_on_animation_finished)

func _physics_process(delta):
	if estado_actual == Estado.AGARRADO:
		return
		
	# Gravedad exacta a la de la cazadora (anulada si está trepando o en escalera)
	if not is_on_floor() and estado_actual not in [Estado.TREPANDO, Estado.EN_ESCALERA]:
		if velocity.y < 0:
			velocity.y += gravity_up * delta
		else:
			velocity.y += gravity_down * delta

	if estado_actual in [Estado.MUERTO, Estado.LEVANTANDOSE]:
		move_and_slide()
		return

	if estado_actual == Estado.DESMAYADO:
		move_and_slide()
		tiempo_desmayado += delta
		if tiempo_desmayado >= 10.0: 
			despertarse()
		return

	match estado_actual:
		Estado.PATRULLANDO:
			comportamiento_patrulla(delta)
		Estado.SOSPECHANDO:
			comportamiento_sospecha(delta)
		Estado.AGRESIVO:
			comportamiento_agresivo()
		Estado.ESPERANDO_MARCADOR:
			velocity.x = 0
			timer_marcador -= delta
			if timer_marcador <= 0:
				if orden_pendiente == 2:
					dar_vuelta()
				estado_actual = Estado.PATRULLANDO
		Estado.SALTANDO:
			velocity.x = direccion_x * SPEED_PATRULLA
			check_ledge_grab()
			if is_on_floor() and velocity.y >= 0:
				estado_actual = Estado.PATRULLANDO
		Estado.TREPANDO:
			velocity.x = 20
			velocity.y = -50
		Estado.CAYENDO_POR_AGUJERO:
			# Lo hacemos caminar hacia adelante ignorando el ray_piso
			velocity.x = direccion_x * SPEED_PATRULLA
			
			# Si dejó de tocar el piso, activamos la bandera de que está en el aire
			if not is_on_floor():
				orden_pendiente = 1 
				
			# Si vuelve a tocar el piso Y ya estuvo en el aire, significa que aterrizó abajo
			if is_on_floor() and orden_pendiente == 1:
				estado_actual = Estado.PATRULLANDO
		Estado.EN_ESCALERA:
			velocity.x = 0
			velocity.y = direccion_escalera * SPEED_ESCALERA

	move_and_slide()
	actualizar_animaciones()

func comportamiento_patrulla(_delta):
	if ray_vision.is_colliding():
		var colision = ray_vision.get_collider()
		if colision and colision.is_in_group("jugador"):
			estado_actual = Estado.AGRESIVO
			return 

	var jugador = get_tree().get_first_node_in_group("jugador")
	if jugador:
		var distancia = global_position.distance_to(jugador.global_position)
		if distancia < 50.0:
			estado_actual = Estado.SOSPECHANDO
			tiempo_sospecha = 0.0
			return

	if ray_muro.is_colliding() or not ray_piso.is_colliding():
		dar_vuelta()
		
	velocity.x = direccion_x * SPEED_PATRULLA

func comportamiento_sospecha(delta):
	velocity.x = direccion_x * SPEED_SOSPECHA
	tiempo_sospecha += delta
	
	if ray_vision.is_colliding():
		var colision = ray_vision.get_collider()
		if colision and colision.is_in_group("jugador"):
			estado_actual = Estado.AGRESIVO
			return
	
	if tiempo_sospecha >= 2.0:
		estado_actual = Estado.PATRULLANDO
		tiempo_sospecha = 0.0

func comportamiento_agresivo():
	var jugador = get_tree().get_first_node_in_group("jugador")
	
	if jugador:
		velocity.x = direccion_x * SPEED_PERSECUCION
		
		var dir_hacia_jugador = sign(jugador.global_position.x - global_position.x)
		if dir_hacia_jugador != 0 and dir_hacia_jugador != direccion_x:
			dar_vuelta()
			
		var distancia = global_position.distance_to(jugador.global_position)
		if distancia > 200.0:
			estado_actual = Estado.SOSPECHANDO
			tiempo_sospecha = 0.0

func dar_vuelta():
	direccion_x *= -1
	ray_muro.target_position.x *= -1
	ray_piso.position.x *= -1
	ray_vision.target_position.x *= -1
	
	wall_check.target_position.x *= -1
	floor_check.target_position.x *= -1

func reproducir_animacion(nombre_animacion):
	if tiene_gorro:
		anim.play(nombre_animacion)
	else:
		anim.play(nombre_animacion + "_sin_gorro")

func actualizar_animaciones():
	anim.flip_h = (direccion_x < 0)
	var offset_base_x = compensacion_sprite if (direccion_x < 0) else 0.0
	
	if estado_actual != Estado.TREPANDO:
		anim.offset.y = 0
		anim.offset.x = offset_base_x
	
	if esta_herido or estado_actual == Estado.TREPANDO:
		return
	
	match estado_actual:
		Estado.PATRULLANDO:
			reproducir_animacion("idle" if velocity.x == 0 else "patrulla_camina")
		Estado.SOSPECHANDO:
			reproducir_animacion("curioso_camina")
		Estado.AGRESIVO:
			reproducir_animacion("corre_y_ataca")
		Estado.ESPERANDO_MARCADOR:
			reproducir_animacion("mira_derecha_izquierda_patrulla")
		Estado.SALTANDO:
			if velocity.y < 0:
				reproducir_animacion("salta")
			else:
				reproducir_animacion("cae")
		Estado.CAYENDO_POR_AGUJERO:
			if is_on_floor():
				reproducir_animacion("patrulla_camina")
			else:
				reproducir_animacion("cae")
		Estado.EN_ESCALERA:
			# Reciclamos la animación de trepar mientras sube o baja
			reproducir_animacion("trepa_escalera")

func recibir_dano():
	if estado_actual == Estado.TREPANDO:
		$CollisionShape2D.set_deferred("disabled", false)
		
	if estado_actual in [Estado.MUERTO, Estado.DESMAYADO, Estado.LEVANTANDOSE]:
		return
		
	vida -= 1
	if vida <= 0:
		estado_actual = Estado.MUERTO
		velocity.x = 0
		reproducir_animacion("danio_cae_al_suelo")
		await anim.animation_finished
		reproducir_animacion("muerto") 
		set_physics_process(false) 
	else:
		esta_herido = true 
		estado_actual = Estado.AGRESIVO 
		velocity.x = 0 
		reproducir_animacion("recibe_danio")
		await anim.animation_finished 
		esta_herido = false 

func puede_recibir_takedown(posicion_jugador_x):
	if estado_actual in [Estado.AGRESIVO, Estado.MUERTO, Estado.AGARRADO, Estado.DESMAYADO, Estado.LEVANTANDOSE, Estado.TREPANDO, Estado.CAYENDO_POR_AGUJERO, Estado.EN_ESCALERA]:
		return false
	if direccion_x == 1 and posicion_jugador_x < global_position.x:
		return true
	elif direccion_x == -1 and posicion_jugador_x > global_position.x:
		return true
	return false

func ser_agarrado():
	estado_actual = Estado.AGARRADO
	$CollisionShape2D.set_deferred("disabled", true)
	velocity = Vector2.ZERO
	reproducir_animacion("agarrado")

func ser_desmayado():
	estado_actual = Estado.DESMAYADO
	tiene_gorro = false
	reproducir_animacion("agarrado_desmayando")
	await anim.animation_finished
	if estado_actual == Estado.DESMAYADO:
		reproducir_animacion("agarrado_desmayando_mantener")

func ser_asesinado():
	estado_actual = Estado.MUERTO
	reproducir_animacion("agarrado_matar")

func soltar_cuerpo(es_muerte):
	set_physics_process(true)
	$CollisionShape2D.set_deferred("disabled", false)
	if es_muerte:
		reproducir_animacion("muerto")
	else:
		tiempo_desmayado = 0.0
		reproducir_animacion("agarrado_desmayado_cae_al_suelo")
		await anim.animation_finished
		if estado_actual == Estado.DESMAYADO:
			reproducir_animacion("desmayado_idle")

func actualizar_movimiento_agarrado(direccion_jugador, facing_left_jugador):
	if estado_actual == Estado.MUERTO or estado_actual == Estado.DESMAYADO:
		return 
	anim.flip_h = facing_left_jugador
	if direccion_jugador != 0:
		reproducir_animacion("agarrado_camina")
	else:
		reproducir_animacion("agarrado")

func ser_neutralizado():
	estado_actual = Estado.MUERTO
	velocity = Vector2.ZERO
	reproducir_animacion("agarrado_matar")
	await anim.animation_finished
	reproducir_animacion("muerto")
	set_physics_process(false)
	
func recibir_flechazo(tipo_flecha):
	if estado_actual == Estado.TREPANDO:
		$CollisionShape2D.set_deferred("disabled", false)
		
	if estado_actual in [Estado.MUERTO, Estado.DESMAYADO, Estado.LEVANTANDOSE]:
		return
		
	if tipo_flecha == "letal":
		estado_actual = Estado.MUERTO
		velocity.x = 0
		reproducir_animacion("danio_cae_al_suelo")
		await anim.animation_finished
		reproducir_animacion("muerto")
		set_physics_process(false)
	elif tipo_flecha == "desmayante":
		estado_actual = Estado.DESMAYADO
		tiene_gorro = false
		tiempo_desmayado = 0.0
		velocity.x = 0
		$CollisionShape2D.set_deferred("disabled", false)
		reproducir_animacion("desmayado_idle")

func despertarse():
	estado_actual = Estado.LEVANTANDOSE
	tiempo_desmayado = 0.0
	anim.play("empieza_a_levantarse")
	await anim.animation_finished
	anim.play("mira_izquierda_derecha_levantandose")
	await anim.animation_finished
	anim.play("se_levanta")
	await anim.animation_finished
	estado_actual = Estado.SOSPECHANDO
	tiempo_sospecha = 0.0

func recibir_orden_marcador(orden, tiempo):
	if estado_actual != Estado.PATRULLANDO:
		return
	if orden == 0:
		dar_vuelta()
	elif orden == 1:
		estado_actual = Estado.ESPERANDO_MARCADOR
		timer_marcador = tiempo
		orden_pendiente = 1
	elif orden == 2:
		estado_actual = Estado.ESPERANDO_MARCADOR
		timer_marcador = tiempo
		orden_pendiente = 2
	elif orden == 3: 
		estado_actual = Estado.SALTANDO
		velocity.y = JUMP_VELOCITY
	elif orden == 4:
		estado_actual = Estado.CAYENDO_POR_AGUJERO
		orden_pendiente = 0 
	elif orden == 5: # Subir Escalera
		estado_actual = Estado.EN_ESCALERA
		direccion_escalera = -1
	elif orden == 6: # Bajar Escalera
		estado_actual = Estado.EN_ESCALERA
		direccion_escalera = 1

func check_ledge_grab():
	if is_on_wall() and wall_check.is_colliding() and not floor_check.is_colliding() and velocity.y >= 0:
		ejecutar_trepada()

func ejecutar_trepada():
	estado_actual = Estado.TREPANDO
	velocity = Vector2.ZERO
	
	$CollisionShape2D.set_deferred("disabled", true)
	
	anim.offset.y = 2
	anim.offset.x = 0

	reproducir_animacion("trepa_esquina")
	anim.frame = 0

func soltar_escalera():
	if estado_actual == Estado.EN_ESCALERA:
		estado_actual = Estado.PATRULLANDO
		velocity.y = 0

func _on_animation_finished():
	var terminada = anim.animation
	
	if terminada == "trepa_esquina" or terminada == "trepa_esquina_sin_gorro":
		var empuje_x = 50 * direccion_x
		var subida_y = 0 
		
		global_position += Vector2(empuje_x, subida_y)
		
		anim.offset.x = compensacion_sprite if (direccion_x < 0) else 0.0
		anim.offset.y = 0
		
		$CollisionShape2D.set_deferred("disabled", false)
		estado_actual = Estado.PATRULLANDO
