extends Area2D

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.is_in_group("jugador"):
		# Deshabilitamos movimiento del jugador
		if "accion_bloqueante" in body:
			body.accion_bloqueante = true
			body.velocity = Vector2.ZERO
		
		var ui_msg = get_tree().current_scene.get_node_or_null("PantallaMensajes")
		if ui_msg:
			ui_msg.mostrar_fin_demo()
