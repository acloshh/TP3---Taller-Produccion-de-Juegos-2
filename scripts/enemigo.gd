extends CharacterBody2D

enum Estado { PATRULLANDO, SOSPECHANDO, AGRESIVO, MUERTO, AGARRADO, DESMAYADO }
var estado_actual = Estado.PATRULLANDO

const SPEED_PATRULLA = 100.0
const SPEED_SOSPECHA = 150
const SPEED_PERSECUCION = 285.0

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var anim = $AnimatedSprite2D
@onready var ray_muro = $RayMuro
@onready var ray_piso = $RayPiso
@onready var ray_vision = $RayVision

var direccion_x = 1
var tiempo_sospecha = 0.0

var vida = 3
var esta_herido = false
var en_pausa_patrulla = false
var tiempo_pausa = 0.0

func _physics_process(delta):
	# Si está agarrado, el jugador controla su posición y no aplicamos gravedad ni movimiento
	if estado_actual == Estado.AGARRADO:
		return
		
	# La gravedad sigue afectando por si muere en el aire
	if not is_on_floor():
		velocity.y += gravity * delta

	# Si está muerto o desmayado, aplicamos gravedad y cortamos la función acá mismo
	if estado_actual == Estado.MUERTO or estado_actual == Estado.DESMAYADO:
		move_and_slide()
		return

	# --- EL RESTO DE TU CÓDIGO NORMAL SIGUE ACÁ ---
	match estado_actual:
		Estado.PATRULLANDO:
			comportamiento_patrulla(delta)
		Estado.SOSPECHANDO:
			comportamiento_sospecha(delta)
		Estado.AGRESIVO:
			comportamiento_agresivo()

	move_and_slide()
	actualizar_animaciones()

func comportamiento_patrulla(delta):
	# 1. Detección Visual... (tu código sigue igual)
	if ray_vision.is_colliding():
		var colision = ray_vision.get_collider()
		if colision and colision.is_in_group("jugador"):
			estado_actual = Estado.AGRESIVO
			return

	# 2. Detección por Proximidad... (tu código sigue igual)
	var jugador = get_tree().get_first_node_in_group("jugador")
	if jugador:
		var distancia = global_position.distance_to(jugador.global_position)
		if distancia < 50.0:
			estado_actual = Estado.SOSPECHANDO
			tiempo_sospecha = 0.0
			return

	# --- NUEVO: Chequeo de pausa ---
	if en_pausa_patrulla:
		velocity.x = 0
		tiempo_pausa -= delta
		if tiempo_pausa <= 0:
			en_pausa_patrulla = false
		return # Cortamos la función acá para que se quede en idle
	# -------------------------------

	# 3. Patrullaje normal
	if ray_muro.is_colliding() or not ray_piso.is_colliding():
		dar_vuelta()
		
	velocity.x = direccion_x * SPEED_PATRULLA


func comportamiento_sospecha(delta):
	# Se queda quieto mirando/buscando
	velocity.x = direccion_x * SPEED_SOSPECHA
	tiempo_sospecha += delta
	
	# Si mientras sospecha, te cruzás por su visión, se pone agresivo
	if ray_vision.is_colliding():
		var colision = ray_vision.get_collider()
		if colision and colision.is_in_group("jugador"):
			estado_actual = Estado.AGRESIVO
			return
	
	# Después de 2 segundos, si no vio nada, vuelve a patrullar
	if tiempo_sospecha >= 2.0:
		estado_actual = Estado.PATRULLANDO
		tiempo_sospecha = 0.0

func comportamiento_agresivo():
	var jugador = get_tree().get_first_node_in_group("jugador")
	
	if jugador:
		# Persigue al jugador
		velocity.x = direccion_x * SPEED_PERSECUCION
		
		# Si el jugador lo salta y le queda en la espalda, el enemigo se da vuelta
		var dir_hacia_jugador = sign(jugador.global_position.x - global_position.x)
		if dir_hacia_jugador != 0 and dir_hacia_jugador != direccion_x:
			dar_vuelta()
			
		# Si te alejás mucho (más de 200px), pierde el rastro y pasa a sospecha
		var distancia = global_position.distance_to(jugador.global_position)
		if distancia > 200.0:
			estado_actual = Estado.SOSPECHANDO
			tiempo_sospecha = 0.0

func dar_vuelta():
	direccion_x *= -1
	
	# Invertimos la dirección física de todos los sensores
	ray_muro.target_position.x *= -1
	ray_piso.position.x *= -1
	ray_vision.target_position.x *= -1

func actualizar_animaciones():
	anim.flip_h = (direccion_x < 0)
	
	# Si está reproduciendo la animación de daño, cortamos la función acá
	if esta_herido:
		return
	
	match estado_actual:
		Estado.PATRULLANDO:
			anim.play("patrulla_camina")
		Estado.SOSPECHANDO:
			anim.play("curioso_camina")
		Estado.AGRESIVO:
			anim.play("corre_y_ataca")
		Estado.AGARRADO:
			anim.play("agarrado")
		Estado.DESMAYADO:
			anim.play("desmayado_idle")

func forzar_sospecha():
	if estado_actual == Estado.PATRULLANDO:
		estado_actual = Estado.SOSPECHANDO
		tiempo_sospecha = 0.0

func recibir_dano():
	if estado_actual == Estado.MUERTO or estado_actual == Estado.DESMAYADO:
		return
		
	vida -= 1
	
	if vida <= 0:
		estado_actual = Estado.MUERTO
		velocity.x = 0
		anim.play("danio_cae_al_suelo")
		await anim.animation_finished
		queue_free()
	else:
		esta_herido = true # Bloqueamos otras animaciones
		estado_actual = Estado.AGRESIVO # Se enoja porque le disparaste
		velocity.x = 0 # Opcional: hacemos que el golpe lo frene un instante
		
		anim.play("recibe_danio")
		await anim.animation_finished # Esperamos que termine la animación
		
		esta_herido = false # Liberamos las animaciones de nuevo

# --- FUNCIONES DE SIGILO Y REHÉN ---

func puede_recibir_takedown(posicion_jugador_x):
	# No se deja agarrar si ya está en combate, muerto, agarrado o desmayado
	if estado_actual == Estado.AGRESIVO or estado_actual == Estado.MUERTO or estado_actual == Estado.AGARRADO or estado_actual == Estado.DESMAYADO:
		return false
		
	# Chequea si el jugador está a sus espaldas
	if direccion_x == 1 and posicion_jugador_x < global_position.x:
		return true
	elif direccion_x == -1 and posicion_jugador_x > global_position.x:
		return true
		
	return false

func ser_agarrado():
	velocity = Vector2.ZERO
	set_physics_process(false)
	# APAGAMOS LA COLISIÓN para que no empuje al jugador (usamos set_deferred por seguridad del motor)
	$CollisionShape2D.set_deferred("disabled", true) 
	anim.play("agarrado")
	
func actualizar_movimiento_agarrado(direccion_jugador, facing_left_jugador):
	# PROTECCIÓN: Si lo estamos matando o desmayando, ignoramos este bloque para no romper la animación
	if estado_actual == Estado.MUERTO or estado_actual == Estado.DESMAYADO:
		return 
		
	anim.flip_h = facing_left_jugador
	if direccion_jugador != 0:
		anim.play("agarrado_camina")
	else:
		anim.play("agarrado")

func ser_desmayado():
	estado_actual = Estado.DESMAYADO
	anim.play("agarrado_desmayando")

func ser_asesinado():
	estado_actual = Estado.MUERTO
	anim.play("agarrado_matar")
	
func soltar_agarre():
	set_physics_process(true)
	# PRENDEMOS LA COLISIÓN si lo volvés a soltar vivo con el mismo botón
	$CollisionShape2D.set_deferred("disabled", false)
	anim.play("desmayado_idle")

func soltar_cuerpo(es_muerte):
	# Recién acá le devolvemos el peso y la colisión para que caiga rendido al piso
	set_physics_process(true)
	$CollisionShape2D.set_deferred("disabled", false)
	if es_muerte:
		anim.play("muerto")
	else:
		anim.play("desmayado_idle")

func ser_neutralizado():
	estado_actual = Estado.MUERTO
	velocity = Vector2.ZERO
	anim.play("agarrado_matar")
	await anim.animation_finished
	queue_free()
	
func recibir_flechazo(tipo_flecha):
	if estado_actual == Estado.MUERTO or estado_actual == Estado.DESMAYADO:
		return
		
	if tipo_flecha == "letal":
		estado_actual = Estado.MUERTO
		velocity.x = 0
		anim.play("danio_cae_al_suelo")
		await anim.animation_finished
		queue_free()
	elif tipo_flecha == "desmayante":
		estado_actual = Estado.DESMAYADO
		velocity.x = 0
		$CollisionShape2D.set_deferred("disabled", false)
		anim.play("desmayado_idle")

func ejecutar_marcador(accion, tiempo):
	# Solo le hace caso al marcador si está tranquilo patrullando
	if estado_actual != Estado.PATRULLANDO:
		return
		
	if accion == 0: # DAR_VUELTA
		dar_vuelta()
	elif accion == 1: # ESPERAR_Y_SEGUIR
		en_pausa_patrulla = true
		tiempo_pausa = tiempo
		velocity.x = 0
	elif accion == 2: # ESPERAR_Y_DAR_VUELTA
		en_pausa_patrulla = true
		tiempo_pausa = tiempo
		velocity.x = 0
		dar_vuelta()
		
