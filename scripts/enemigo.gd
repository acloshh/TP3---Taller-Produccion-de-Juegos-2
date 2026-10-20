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
var ancho_colision_original = 0.0
var tiempo_en_escalera = 0.0 

# --- EFECTOS VISUALES ---
@export var escena_sangre: PackedScene

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

# --- NUEVO SISTEMA DE DETECCIÓN VISUAL ---
var estado_alerta = 0 # 0: Tranquilo, 1: Sospecha, 2: Alerta
var nivel_sospecha = 0.0 # 0 a 100
var jugador_en_vision = null # Guarda referencia al jugador si está en el cono

func _ready():
	anim.animation_finished.connect(_on_animation_finished)
	
	# Hace única la colisión y guarda su tamaño original
	$CollisionShape2D.shape = $CollisionShape2D.shape.duplicate()
	ancho_colision_original = $CollisionShape2D.shape.size.x
	
	cambiar_icono_estado("")

func _physics_process(delta):
	procesar_vision(delta)
	
	if estado_actual == Estado.AGARRADO:
		return
		
	# Gravedad proporcional (anulada si está trepando o en escalera)
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

	# Pausa de la IA si está procesando el knockup por daño
	if esta_herido:
		move_and_slide()
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
				$CollisionShape2D.shape.size.x = ancho_colision_original 
		Estado.TREPANDO:
			velocity.x = 20
			velocity.y = -50
		Estado.CAYENDO_POR_AGUJERO:
			velocity.x = direccion_x * SPEED_PATRULLA
			if not is_on_floor():
				orden_pendiente = 1 
			if is_on_floor() and orden_pendiente == 1:
				estado_actual = Estado.PATRULLANDO
		Estado.EN_ESCALERA:
			velocity.x = 0
			velocity.y = direccion_escalera * SPEED_ESCALERA
			tiempo_en_escalera += delta
			
			# Al bajar y tocar el piso inferior
			if direccion_escalera == 1 and is_on_floor() and tiempo_en_escalera > 0.1:
				soltar_escalera()

	move_and_slide()

	# Chequeo directo por colisión física contra el jugador
	if estado_actual not in [Estado.MUERTO, Estado.DESMAYADO, Estado.AGARRADO]:
		for i in range(get_slide_collision_count()):
			var colision = get_slide_collision(i)
			var collider = colision.get_collider()
			if collider and collider.is_in_group("jugador"):
				if collider.has_method("morir"):
					collider.morir("Un guardia te ha descubierto y ejecutado.")

	actualizar_animaciones()

# --- SEGURIDAD DE ESCALERA ---

func abortar_escalera():
	if estado_actual == Estado.EN_ESCALERA:
		call_deferred("set_collision_mask_value", 1, true)
		$CollisionShape2D.shape.size.x = ancho_colision_original

# --- SISTEMA DE ICONO ESTADO ---

func cambiar_icono_estado(animacion_icono):
	if not has_node("IconoEstado"): return
	
	if animacion_icono == "":
		$IconoEstado.hide()
		return
		
	$IconoEstado.show()
	$IconoEstado.play(animacion_icono)
	
	if animacion_icono == "dormido":
		var mod_x = 20.0 if anim.flip_h else -20.0
		$IconoEstado.offset = Vector2(mod_x, 25.0)
		$IconoEstado.scale = Vector2(2.0, 2.0)
	else:
		$IconoEstado.offset = Vector2(0.0, 0.0)
		$IconoEstado.scale = Vector2(1.0, 1.0)

# --- SISTEMA DE SANGRE ---

func generar_sangre():
	if escena_sangre:
		var sangre = escena_sangre.instantiate()
		get_parent().add_child(sangre)
		sangre.global_position = global_position + Vector2(0, -15)

# --- FUNCIONES DE VISIÓN ---

func procesar_vision(delta):
	if esta_herido or estado_actual in [Estado.MUERTO, Estado.DESMAYADO, Estado.AGARRADO]:
		return
		
	if jugador_en_vision:
		ray_vision.target_position = to_local(jugador_en_vision.global_position)
		ray_vision.force_raycast_update() 
		
		if ray_vision.is_colliding():
			bajar_sospecha_gradual(delta)
			return 

		var camuflaje = jugador_en_vision.get("nivel_ocultamiento")
		if camuflaje == null: 
			camuflaje = 0

		var esta_escondido = camuflaje == 2 and (jugador_en_vision.es_sigilo or jugador_en_vision.esta_acostado)
		if esta_escondido:
			bajar_sospecha_gradual(delta)
			return

		if jugador_en_vision.es_sigilo:
			if estado_alerta == 0:
				entrar_estado_sospecha()
			
			var velocidad_deteccion = 60.0 
			if camuflaje == 1:
				velocidad_deteccion = 15.0 
			
			nivel_sospecha += delta * velocidad_deteccion 
			
			if nivel_sospecha >= 100:
				entrar_estado_alerta()
		else:
			entrar_estado_alerta()
	else:
		bajar_sospecha_gradual(delta)

func bajar_sospecha_gradual(delta):
	if estado_alerta == 2:
		estado_alerta = 1
		estado_actual = Estado.SOSPECHANDO
		tiempo_sospecha = 0.0
		nivel_sospecha = 99.0
		cambiar_icono_estado("sospecha")

	if nivel_sospecha > 0:
		nivel_sospecha -= delta * 40
		if nivel_sospecha <= 0:
			nivel_sospecha = 0
			bajar_alerta()

func _on_cono_vision_body_entered(body):
	if body != null and not body.is_queued_for_deletion():
		if body.is_in_group("jugador"):
			jugador_en_vision = body

func _on_cono_vision_body_exited(body):
	if body != null and body.is_in_group("jugador"):
		if not body in $ConoVision.get_overlapping_bodies():
			if jugador_en_vision == body:
				jugador_en_vision = null

func entrar_estado_sospecha():
	abortar_escalera()
	estado_alerta = 1
	estado_actual = Estado.SOSPECHANDO
	tiempo_sospecha = 0.0
	cambiar_icono_estado("sospecha")

func entrar_estado_alerta():
	abortar_escalera()
	estado_alerta = 2
	estado_actual = Estado.AGRESIVO
	cambiar_icono_estado("alerta")

func bajar_alerta():
	estado_alerta = 0
	if estado_actual == Estado.SOSPECHANDO:
		estado_actual = Estado.PATRULLANDO
	cambiar_icono_estado("")

func comportamiento_patrulla(_delta):
	var jugador = get_tree().get_first_node_in_group("jugador")
	if jugador:
		var distancia = global_position.distance_to(jugador.global_position)
		var dir_hacia_jugador = sign(jugador.global_position.x - global_position.x)
		
		var camuflaje = jugador.get("nivel_ocultamiento")
		if camuflaje == null:
			camuflaje = 0

		var esta_escondido = camuflaje == 2 and (jugador.es_sigilo or jugador.esta_acostado)
		
		if esta_escondido:
			add_collision_exception_with(jugador)
		else:
			remove_collision_exception_with(jugador)
			
			if distancia < 20.0 and dir_hacia_jugador == direccion_x:
				entrar_estado_alerta()
				return
			elif distancia < 30.0 and not jugador.es_sigilo and not jugador.esta_acostado: 
				entrar_estado_alerta()
				return

	if ray_muro.is_colliding():
		dar_vuelta()
	elif is_on_floor() and not ray_piso.is_colliding():
		dar_vuelta()
		
	velocity.x = direccion_x * SPEED_PATRULLA

func comportamiento_sospecha(delta):
	velocity.x = 0
	tiempo_sospecha += delta
	
	if tiempo_sospecha >= 3.0 and jugador_en_vision == null:
		bajar_alerta()

func comportamiento_agresivo():
	var jugador = get_tree().get_first_node_in_group("jugador")
	
	if jugador:
		velocity.x = direccion_x * SPEED_PERSECUCION
		
		var dir_hacia_jugador = sign(jugador.global_position.x - global_position.x)
		if dir_hacia_jugador != 0 and dir_hacia_jugador != direccion_x:
			dar_vuelta()
			
		var distancia = global_position.distance_to(jugador.global_position)
		if distancia < 25.0:
			if jugador.has_method("morir"):
				jugador.morir("Un guardia te ha descubierto y ejecutado.")
		elif distancia > 350.0:
			bajar_sospecha_gradual(100.0)

func dar_vuelta():
	direccion_x *= -1
	ray_muro.target_position.x *= -1
	ray_piso.position.x *= -1
	if has_node("ConoVision"):
		$ConoVision.scale.x *= -1 
	
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
			reproducir_animacion("mira_derecha_izquierda_patrulla") 
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
			reproducir_animacion("trepa_escalera")

func recibir_dano(atacante_x = null):
	abortar_escalera()
	$CollisionShape2D.shape.size.x = ancho_colision_original 
	if estado_actual == Estado.TREPANDO:
		$CollisionShape2D.set_deferred("disabled", false)
		
	if estado_actual in [Estado.MUERTO, Estado.DESMAYADO, Estado.LEVANTANDOSE]:
		return
		
	vida -= 1
	
	if vida <= 0:
		morir_general("danio_cae_al_suelo")
	else:
		esta_herido = true 
		nivel_sospecha = 100.0
		entrar_estado_alerta() 
		
		if atacante_x != null:
			var dir_al_atacante = sign(atacante_x - global_position.x)
			if dir_al_atacante != 0 and dir_al_atacante != direccion_x:
				dar_vuelta()
		
		if atacante_x != null:
			var dir_empuje = sign(global_position.x - atacante_x)
			if dir_empuje == 0: 
				dir_empuje = -direccion_x
			velocity.x = dir_empuje * 180.0
		else:
			velocity.x = -direccion_x * 180.0
			
		velocity.y = -300.0
		
		reproducir_animacion("recibe_danio")
		await anim.animation_finished 
		
		velocity.x = 0
		esta_herido = false 

func morir_general(animacion_caida):
	estado_actual = Estado.MUERTO
	velocity.x = 0
	anim.flip_h = not anim.flip_h 
	cambiar_icono_estado("")
	generar_sangre()
	reproducir_animacion(animacion_caida)
	await anim.animation_finished
	reproducir_animacion("muerto") 
	set_physics_process(false)

func puede_recibir_takedown(posicion_jugador_x):
	if estado_actual in [Estado.AGRESIVO, Estado.MUERTO, Estado.AGARRADO, Estado.DESMAYADO, Estado.LEVANTANDOSE, Estado.TREPANDO, Estado.CAYENDO_POR_AGUJERO, Estado.EN_ESCALERA]:
		return false
	if direccion_x == 1 and posicion_jugador_x < global_position.x:
		return true
	elif direccion_x == -1 and posicion_jugador_x > global_position.x:
		return true
	return false

func ser_agarrado():
	abortar_escalera()
	$CollisionShape2D.shape.size.x = ancho_colision_original 
	estado_actual = Estado.AGARRADO
	cambiar_icono_estado("")
	$CollisionShape2D.set_deferred("disabled", true)
	velocity = Vector2.ZERO
	reproducir_animacion("agarrado")

func ser_desmayado():
	$CollisionShape2D.shape.size.x = ancho_colision_original 
	estado_actual = Estado.DESMAYADO
	tiene_gorro = false
	cambiar_icono_estado("dormido")
	reproducir_animacion("agarrado_desmayando")
	await anim.animation_finished
	if estado_actual == Estado.DESMAYADO:
		reproducir_animacion("agarrado_desmayando_mantener")

func ser_asesinado():
	estado_actual = Estado.MUERTO
	cambiar_icono_estado("")
	generar_sangre()
	reproducir_animacion("agarrado_matar")

func soltar_cuerpo(es_muerte):
	set_physics_process(true)
	$CollisionShape2D.set_deferred("disabled", false)
	set_collision_mask_value(1, true)
	
	anim.flip_h = not anim.flip_h 
	
	if es_muerte:
		reproducir_animacion("muerto")
		cambiar_icono_estado("")
	else:
		tiempo_desmayado = 0.0
		cambiar_icono_estado("dormido")
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
	abortar_escalera()
	estado_actual = Estado.MUERTO
	velocity = Vector2.ZERO
	cambiar_icono_estado("")
	generar_sangre()
	reproducir_animacion("agarrado_matar")
	await anim.animation_finished
	reproducir_animacion("muerto")
	set_physics_process(false)
	
func recibir_flechazo(tipo_flecha):
	abortar_escalera()
	$CollisionShape2D.shape.size.x = ancho_colision_original 
	if estado_actual == Estado.TREPANDO:
		$CollisionShape2D.set_deferred("disabled", false)
		
	if estado_actual in [Estado.MUERTO, Estado.DESMAYADO, Estado.LEVANTANDOSE]:
		return
		
	if tipo_flecha == "letal":
		morir_general("danio_cae_al_suelo")
	elif tipo_flecha == "desmayante":
		estado_actual = Estado.DESMAYADO
		tiene_gorro = false
		tiempo_desmayado = 0.0
		velocity.x = 0
		
		anim.flip_h = not anim.flip_h 
		
		cambiar_icono_estado("dormido")
		$CollisionShape2D.set_deferred("disabled", false)
		reproducir_animacion("desmayado_idle")

func despertarse():
	estado_actual = Estado.LEVANTANDOSE
	tiempo_desmayado = 0.0
	cambiar_icono_estado("")
	anim.play("empieza_a_levantarse")
	await anim.animation_finished
	anim.play("mira_izquierda_derecha_levantandose")
	await anim.animation_finished
	anim.play("se_levanta")
	await anim.animation_finished
	entrar_estado_sospecha()

func recibir_orden_marcador(orden, tiempo, marcador = null):
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
	elif orden == 5 or orden == 6: 
		if marcador == null: return
		
		if randf() > 0.5:
			return
		
		estado_actual = Estado.EN_ESCALERA
		$CollisionShape2D.shape.size.x = 10.0 
		tiempo_en_escalera = 0.0 
		
		set_collision_mask_value(1, false)
		
		var colision_escalera = marcador.get_node("CollisionShape2D")
		global_position.x = colision_escalera.global_position.x 
		var centro_real_y = colision_escalera.global_position.y
		
		if global_position.y < centro_real_y:
			direccion_escalera = 1 
		else:
			direccion_escalera = -1 

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
	if estado_actual == Estado.EN_ESCALERA and tiempo_en_escalera > 0.1:
		set_collision_mask_value(1, true)
		$CollisionShape2D.shape.size.x = ancho_colision_original
		
		if direccion_escalera == -1: 
			estado_actual = Estado.SALTANDO
			velocity.y = JUMP_VELOCITY * 0.7
			position.y -= 4
		else: 
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
