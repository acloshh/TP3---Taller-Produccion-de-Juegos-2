extends CharacterBody2D

const SPEED_COMBATE = 300.0
const SPEED_SIGILO = 150.0
const SPEED_ACOSTADO = 100.0
const SPEED_ARRASTRAR_REHEN = 40.0
const JUMP_VELOCITY = -700.0
var gravity_up = 1800.0
var gravity_down = 2200.0
const DISTANCIA_REHEN = 16
var nivel_ocultamiento = 0

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

@export var flecha_escena: PackedScene

@onready var anim = $AnimatedSprite2D
@onready var colision_parado = $ColisionParado
@onready var colision_sigilo = $ColisionSigilo
@onready var colision_acostado = $ColisionAcostado
@onready var ledge_collider = $LedgeCollider
@onready var wall_check = $WallCheck
@onready var floor_check = $FloorCheck
@onready var top_check = $TopCheck
@onready var hitbox = $Hitbox
@onready var hitbox_shape = $Hitbox/CollisionShape2D
@onready var area_takedown = $AreaTakedown
@onready var popup_acciones = $PopUpAcciones
@onready var linea_trayectoria = $LineaTrayectoria

# --- VARIABLES DE INTERFAZ ACTUALIZADAS ---
@onready var iconos_flechas = $Interfaz/IconosFlecha
@onready var texto_flecha = $Interfaz/TextoFlecha
@onready var texto_melee = $Interfaz/TextoMelee
@onready var iconos_melee = $Interfaz/IconosMelee
@onready var punto_disparo = $PuntoDisparo

var pos_inicial_disparo_x = 0.0

# --- ESTADOS PRINCIPALES Y AJUSTES DE SIMETRÍA ---
var es_sigilo = false
var esta_acostado = false
var facing_left = false
var is_hanging = false
var accion_bloqueante = false
var enemigo_agarrado = null

# --- SISTEMA DE ESCALERAS ---
var zona_de_escalera = false
var pos_x_escalera = 0.0
var trepando_escalera = false
const SPEED_TREPAR = 150.0
var ancho_colision_original = 0.0 
var pos_x_colision_original = 0.0 
var timer_cooldown_escalera = 0.0 

# Ajustá estos dos valores si necesitás acercar/alejar las colisiones o centrar el dibujo al girar:
var distancia_frente = 15.0
var compensacion_sprite = 0

# --- SISTEMAS DE ARMAS Y COMBOS ---
var is_aiming = false
var fuerza_arco = 50.0
var direccion_tiro = Vector2.RIGHT
var tipo_flecha = "letal"
var arma_cuerpo_a_cuerpo = "cuchillo"
var combo_paso = 0
var ataque_encolado = false

func _ready():
	colision_parado.shape = colision_parado.shape.duplicate()
	ancho_colision_original = colision_parado.shape.size.x
	pos_x_colision_original = colision_parado.position.x

	hitbox_shape.disabled = true
	popup_acciones.hide()
	anim.animation_finished.connect(_on_animation_finished)
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	
	colision_parado.disabled = false
	colision_sigilo.disabled = true
	colision_acostado.disabled = true
	
	pos_inicial_disparo_x = abs(punto_disparo.position.x)
	
	# Reproducimos la animación inicial de las armas
	iconos_flechas.play(tipo_flecha)
	texto_flecha.text = "F. Letal"
	
	texto_melee.text = "Cuchillo"
	iconos_melee.play("cuchillo")

func _physics_process(delta):
	if timer_cooldown_escalera > 0.0:
		timer_cooldown_escalera -= delta

	# Entrada a la escalera
	if zona_de_escalera and not trepando_escalera and not accion_bloqueante and timer_cooldown_escalera <= 0.0:
		if Input.is_action_pressed("arriba") or Input.is_action_pressed("abajo"):
			trepando_escalera = true
			colision_parado.shape.size.x = 8.0 
			colision_parado.position.x = 0.0 
			
			# Desactivamos colisión con el terreno (Capa 1) para atravesar bloques de plataformas
			set_collision_mask_value(1, false)
			ledge_collider.disabled = true 
			
			global_position.x = pos_x_escalera 
			velocity = Vector2.ZERO
			es_sigilo = false
			esta_acostado = false
			is_hanging = false

	if trepando_escalera:
		var direccion_y = Input.get_axis("arriba", "abajo")
		velocity.y = direccion_y * SPEED_TREPAR
		velocity.x = 0
		
		if direccion_y != 0:
			anim.play("trepa_escalera") 
		else:
			anim.play("escalera_idle")
			
		# Salto para soltar escalera
		if Input.is_action_just_pressed("saltar"):
			# Probamos si al activar la colisión chocaríamos con la tierra/plataforma
			set_collision_mask_value(1, true)
			var choca_con_bloque = test_move(global_transform, Vector2.ZERO)
			
			if choca_con_bloque:
				# Si da verdadero, estamos dentro de un bloque. Apagamos la colisión y anulamos el salto.
				set_collision_mask_value(1, false)
			else:
				# Si está libre, se suelta y salta normal.
				trepando_escalera = false
				colision_parado.shape.size.x = ancho_colision_original 
				colision_parado.position.x = pos_x_colision_original 
				velocity.y = JUMP_VELOCITY * 0.8
				timer_cooldown_escalera = 0.3 
				
		move_and_slide()
		return

	var should_disable_ledge = false
	if not is_hanging:
		should_disable_ledge = floor_check.is_colliding() or velocity.y < 0 or top_check.is_colliding()
	ledge_collider.disabled = should_disable_ledge

	check_ledge_grab()

	var direction = Input.get_axis("mover_izq", "mover_der")

	if Input.is_action_just_pressed("cambiar_postura") and not accion_bloqueante:
		if enemigo_agarrado != null:
			enemigo_agarrado.ser_desmayado()
			popup_acciones.hide()
			ejecutar_accion_bloqueante("desmaya_enemigo")
		else:
			if es_sigilo:
				if not top_check.is_colliding():
					es_sigilo = false
			else:
				es_sigilo = true

	if Input.is_physical_key_pressed(KEY_R):
		get_tree().reload_current_scene()

	var quiere_acostarse = Input.is_action_pressed("abajo") and is_on_floor() and not is_hanging and not accion_bloqueante
	var bloqueado_acostado = esta_acostado and top_check.is_colliding()
	esta_acostado = quiere_acostarse or bloqueado_acostado

	if esta_acostado:
		colision_parado.disabled = true
		colision_sigilo.disabled = true
		colision_acostado.disabled = false
	elif es_sigilo and is_on_floor() and not is_hanging:
		colision_parado.disabled = true
		colision_sigilo.disabled = false
		colision_acostado.disabled = true
	else:
		colision_parado.disabled = false
		colision_sigilo.disabled = true
		colision_acostado.disabled = true

	if Input.is_action_just_pressed("atraer") and is_on_floor() and not is_hanging and not accion_bloqueante:
		ejecutar_accion_bloqueante("atrae_en_posicion_de_sigilo" if es_sigilo else "atrae_en_posicion_de_combate")

	if Input.is_action_just_pressed("agarre") and not accion_bloqueante:
		if enemigo_agarrado == null:
			var cuerpos = area_takedown.get_overlapping_bodies()
			for cuerpo in cuerpos:
				if cuerpo.is_in_group("enemigo") and cuerpo.is_inside_tree() and cuerpo.has_method("puede_recibir_takedown"):
					if cuerpo.puede_recibir_takedown(global_position.x):
						enemigo_agarrado = cuerpo
						enemigo_agarrado.ser_agarrado()
						popup_acciones.show()
						es_sigilo = false
						ejecutar_accion_bloqueante("agarra_enemigo")
						break
		else:
			enemigo_agarrado.soltar_cuerpo(false)
			enemigo_agarrado = null
			popup_acciones.hide()

	if Input.is_action_just_pressed("atacar") and not is_hanging:
		if enemigo_agarrado != null:
			enemigo_agarrado.ser_asesinado()
			popup_acciones.hide()
			ejecutar_accion_bloqueante("mata_enemigo")
		elif not is_aiming:
			manejar_combo_ataque()
			
	if Input.is_action_pressed("apuntar") and not is_hanging and enemigo_agarrado == null and not accion_bloqueante:
		is_aiming = true
		
		var vector_apuntado = Input.get_vector("mover_izq", "mover_der", "arriba", "abajo")
		if vector_apuntado != Vector2.ZERO:
			direccion_tiro = vector_apuntado.normalized()
			if direccion_tiro.x < 0:
				facing_left = true
			elif direccion_tiro.x > 0:
				facing_left = false
		else:
			direccion_tiro = Vector2(-1.0 if facing_left else 1.0, 0.0)
			
		if Input.is_action_pressed("disparar"):
			fuerza_arco += 1200 * delta 
			fuerza_arco = clamp(fuerza_arco, 50.0, 1500.0) 
			actualizar_trayectoria()
		else:
			if linea_trayectoria.get_point_count() > 0:
				linea_trayectoria.clear_points() 
			
		if Input.is_action_just_released("disparar"):
			disparar_flecha()
			fuerza_arco = 50.0 

	elif Input.is_action_just_released("apuntar") and is_aiming:
		is_aiming = false
		fuerza_arco = 50.0
		if linea_trayectoria.get_point_count() > 0:
			linea_trayectoria.clear_points()

	if facing_left:
		hitbox.position.x = -distancia_frente
		hitbox_shape.position.x = -abs(hitbox_shape.position.x)
		area_takedown.position.x = -distancia_frente
		ledge_collider.position.x = -distancia_frente
		punto_disparo.position.x = -40.0
		wall_check.position.x = -distancia_frente
		wall_check.target_position.x = 0
	else:
		hitbox.position.x = distancia_frente
		hitbox_shape.position.x = abs(hitbox_shape.position.x)
		area_takedown.position.x = distancia_frente
		ledge_collider.position.x = distancia_frente
		punto_disparo.position.x = 40.0
		wall_check.position.x = distancia_frente
		wall_check.target_position.x = 0
		
	if is_hanging:
		velocity = Vector2.ZERO
		var trepar_hacia_pared = (not facing_left and Input.is_action_just_pressed("mover_der")) or (facing_left and Input.is_action_just_pressed("mover_izq"))
		var soltarse_hacia_atras = (not facing_left and Input.is_action_just_pressed("mover_izq")) or (facing_left and Input.is_action_just_pressed("mover_der"))
		
		if Input.is_action_just_pressed("arriba") or trepar_hacia_pared:
			is_hanging = false
			ejecutar_accion_bloqueante("trepa")
		elif Input.is_action_just_pressed("abajo") or soltarse_hacia_atras:
			is_hanging = false
			position.y += 2 
	else:
		var esta_trepando = (accion_bloqueante and anim.animation == "trepa")
		
		if not is_aiming and not accion_bloqueante:
			if direction < 0:
				facing_left = false if enemigo_agarrado != null else true
			elif direction > 0:
				facing_left = true if enemigo_agarrado != null else false

		if not is_on_floor():
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

		if Input.is_action_just_pressed("saltar") and is_on_floor() and not accion_bloqueante and not esta_acostado and not (es_sigilo and top_check.is_colliding()):
			velocity.y = JUMP_VELOCITY
			es_sigilo = false 

		if Input.is_action_just_released("saltar") and velocity.y < 0:
			velocity.y *= 0.5

	if enemigo_agarrado != null:
		var offset_x = -DISTANCIA_REHEN if facing_left else DISTANCIA_REHEN
		var offset_y = 10
		enemigo_agarrado.global_position = global_position + Vector2(offset_x, offset_y)
		if enemigo_agarrado.has_method("actualizar_movimiento_agarrado"):
			enemigo_agarrado.actualizar_movimiento_agarrado(direction, facing_left)

	update_animation(direction)
	move_and_slide()

	if Input.is_action_just_pressed("cambiar_arma"):
		if tipo_flecha == "letal":
			tipo_flecha = "desmayante"
			texto_flecha.text = "F. Desmayante"
		else:
			tipo_flecha = "letal"
			texto_flecha.text = "F. Letal"
		iconos_flechas.play(tipo_flecha)

	if Input.is_action_just_pressed("cambiar_melee"):
		if arma_cuerpo_a_cuerpo == "cuchillo":
			arma_cuerpo_a_cuerpo = "puño"
			texto_melee.text = "Puño"
			iconos_melee.play("punio")
		else:
			arma_cuerpo_a_cuerpo = "cuchillo"
			texto_melee.text = "Cuchillo"
			iconos_melee.play("cuchillo")
			
	# --- DETECCIÓN DE VEGETACIÓN ---
	nivel_ocultamiento = 0
	var arbol = get_tree()
	if arbol and arbol.current_scene:
		var mapa = arbol.current_scene.get_node_or_null("TileMapLayer2")
		if mapa:
			var pos_celda = mapa.local_to_map(mapa.to_local(global_position))
			var datos_celda = mapa.get_cell_tile_data(pos_celda)
			if datos_celda:
				nivel_ocultamiento = datos_celda.get_custom_data("tipo_ocultamiento")

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

func actualizar_trayectoria():
	if linea_trayectoria.get_point_count() > 0:
		linea_trayectoria.clear_points()
		
	var vel_simulada = direccion_tiro * fuerza_arco
	punto_disparo.position.y = 35.0
		
	var pos_simulada = punto_disparo.position
	linea_trayectoria.add_point(pos_simulada)
	
	var paso_tiempo = 0.05
	for i in range(30):
		vel_simulada.y += gravity_up * paso_tiempo
		pos_simulada += vel_simulada * paso_tiempo
		linea_trayectoria.add_point(pos_simulada)

func disparar_flecha():
	if flecha_escena:
		var nueva_flecha = flecha_escena.instantiate()
		nueva_flecha.global_position = punto_disparo.global_position
		nueva_flecha.velocity = direccion_tiro * fuerza_arco
		nueva_flecha.tipo = tipo_flecha
		get_parent().add_child(nueva_flecha)

func check_ledge_grab():
	if not is_hanging and not floor_check.is_colliding() and not accion_bloqueante:
		if wall_check.is_colliding() and (is_on_floor() or abs(velocity.y) < 10.0) and velocity.y >= 0:
			is_hanging = true
			velocity = Vector2.ZERO

func update_animation(direction):
	anim.flip_h = facing_left
	var offset_base_x = compensacion_sprite if facing_left else 0.0
	
	if not is_hanging and anim.animation != "trepa":
		anim.offset.y = 0
		anim.offset.x = offset_base_x
		
	if accion_bloqueante or trepando_escalera:
		return
		
	if is_hanging:
		anim.offset.y = 5
		anim.offset.x = offset_base_x + (-5.0 if facing_left else 5.0)
		anim.play("trepa")
		anim.pause()
		anim.frame = 0
	elif is_aiming:
		anim.play("prepara_el_arco")
	elif enemigo_agarrado != null:
		if direction != 0:
			anim.play("camina_con_enemigo_agarrado")
		else:
			anim.play("camina_con_enemigo_agarrado")
			anim.pause()
			anim.frame = 0
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
	
	if "combo" in terminada:
		hitbox_shape.disabled = true
		if ataque_encolado:
			ataque_encolado = false
			combo_paso += 1
			ejecutar_accion_bloqueante("combo_" + arma_cuerpo_a_cuerpo + "_" + str(combo_paso))
			hitbox_shape.disabled = false
			return 
		
	if terminada == "mata_enemigo" or terminada == "desmaya_enemigo":
		hitbox_shape.disabled = true
		if enemigo_agarrado != null:
			var es_muerte = (terminada == "mata_enemigo")
			enemigo_agarrado.soltar_cuerpo(es_muerte)
			enemigo_agarrado = null
		accion_bloqueante = false
		return
		
	if terminada == "trepa":
		var direccion = -1 if anim.flip_h else 1
		var empuje_x = 25 * direccion
		var subida_y = 12
		global_position += Vector2(empuje_x, subida_y)
		anim.offset.x = compensacion_sprite if facing_left else 0.0
		anim.offset.y = 0
		accion_bloqueante = false
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

func entrar_zona_escalera(centro_x):
	zona_de_escalera = true
	pos_x_escalera = centro_x

func salir_zona_escalera():
	zona_de_escalera = false
	if trepando_escalera:
		trepando_escalera = false
		colision_parado.shape.size.x = ancho_colision_original 
		colision_parado.position.x = pos_x_colision_original 
		
		# Cambios aplicados de forma segura con call_deferred
		ledge_collider.set_deferred("disabled", false)
		call_deferred("set_collision_mask_value", 1, true)
		
		# Si salía hacia arriba, lo acomodamos sobre la plataforma
		if Input.is_action_pressed("arriba"):
			position.y -= 4
