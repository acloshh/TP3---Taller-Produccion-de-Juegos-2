extends AnimatedSprite2D

var altura_suelo = 0.0
var hay_suelo = false

func _ready():
	await get_tree().physics_frame
	
	if has_node("RayCast2D"):
		var ray_suelo = $RayCast2D
		ray_suelo.collision_mask = 1 
		ray_suelo.force_raycast_update()
		
		if ray_suelo.is_colliding():
			# Guardamos la coordenada del piso para usarla después
			altura_suelo = ray_suelo.get_collision_point().y + 15
			hay_suelo = true
			
	# La salpicadura se reproduce arriba, donde recibió el golpe
	play("salpicar")
	animation_finished.connect(_on_animation_finished)

func _on_animation_finished():
	if animation == "salpicar":
		# Apenas termina de salpicar, bajamos el nodo al nivel de la tierra
		if hay_suelo:
			global_position.y = altura_suelo
			
		play("charco")
		
		await get_tree().create_timer(5.0).timeout
		var tween = create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 1.5)
		await tween.finished
		queue_free()
