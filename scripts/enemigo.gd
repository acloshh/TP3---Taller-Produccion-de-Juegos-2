extends CharacterBody2D

enum Estado { PATRULLANDO, SOSPECHANDO, AGRESIVO, MUERTO, AGARRADO, DESMAYADO }
var estado_actual = Estado.PATRULLANDO

const SPEED_PATRULLA = 40.0
const SPEED_PERSECUCION = 110.0

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var anim = $AnimatedSprite2D
@onready var ray_muro = $RayMuro
@onready var ray_piso = $RayPiso
@onready var ray_vision = $RayVision

var direccion_x = 1
var tiempo_sospecha = 0.0

var vida = 3
var esta_herido = false

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
			comportamiento_patrulla()
		Estado.SOSPECHANDO:
			comportamiento_sospecha(delta)
		Estado.AGRESIVO:
			comportamiento_agresivo()

	move_and_slide()
	actualizar_animaciones()

func comportamiento_patrulla():
	# 1. Detección Visual (Alerta Roja inmediata si te ve de frente)
	if ray_vision.is_colliding():
		var colision = ray_vision.get_collider()
		if colision and colision.is_in_group("jugador"):
			estado_actual = Estado.AGRESIVO
			return # Cortamos la ejecución acá para que deje de patrullar

	# 2. Detección por Proximidad (Alerta Amarilla si te ponés al lado)
	var jugador = get_tree().get_first_node_in_group("jugador")
	if jugador:
		var distancia = global_position.distance_to(jugador.global_position)
		if distancia < 50.0:
			estado_actual = Estado.SOSPECHANDO
			tiempo_sospecha = 0.0
			return

	# 3. Patrullaje normal
	if ray_muro.is_colliding() or not ray_piso.is_colliding():
		dar_vuelta()
		
	velocity.x = direccion_x * SPEED_PATRULLA

func comportamiento_sospecha(delta):
	# Se queda quieto mirando/buscando
	velocity.x = 0
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
			anim.play("patrullar")
		Estado.SOSPECHANDO:
			anim.play("alerta_amarilla")
		Estado.AGRESIVO:
			anim.play("alerta_roja")
		Estado.AGARRADO:
			anim.play("dañado") 
		Estado.DESMAYADO:
			anim.play("desmayado")
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
		anim.play("muerto")
		await anim.animation_finished
		queue_free()
	else:
		esta_herido = true # Bloqueamos otras animaciones
		estado_actual = Estado.AGRESIVO # Se enoja porque le disparaste
		velocity.x = 0 # Opcional: hacemos que el golpe lo frene un instante
		
		anim.play("dañado")
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
	estado_actual = Estado.AGARRADO
	# Apagamos colisión para que lo puedas arrastrar sin que choque
	$CollisionShape2D.set_deferred("disabled", true)
	velocity = Vector2.ZERO
	anim.play("agarrado")

func soltar_agarre():
	estado_actual = Estado.DESMAYADO
	velocity.x = 0
	# Volvemos a prender la colisión para que caiga contra el piso
	$CollisionShape2D.set_deferred("disabled", false)
	anim.play("desmayado")

func ser_neutralizado():
	estado_actual = Estado.MUERTO
	velocity = Vector2.ZERO
	anim.play("muerto")
	await anim.animation_finished
	queue_free()
	
func recibir_flechazo(tipo_flecha):
	if estado_actual == Estado.MUERTO or estado_actual == Estado.DESMAYADO:
		return
		
	if tipo_flecha == "letal":
		estado_actual = Estado.MUERTO
		velocity.x = 0
		anim.play("muerto")
		await anim.animation_finished
		queue_free()
	elif tipo_flecha == "desmayante":
		estado_actual = Estado.DESMAYADO
		velocity.x = 0
		$CollisionShape2D.set_deferred("disabled", false)
		anim.play("desmayado")
