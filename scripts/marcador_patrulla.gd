extends Area2D

@export_enum("Solo Dar Vuelta", "Frenar y Seguir", "Frenar y Dar Vuelta", "Saltar Obstaculo", "Caer al Vacio", "Subir Escalera", "Bajar Escalera") var orden: int = 0
@export var tiempo_de_espera: float = 2.0

func _ready():
	hide()
	body_entered.connect(_on_body_entered)
	# Nueva señal para cuando termina de subir/bajar
	body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body.is_in_group("enemigo") and body.has_method("recibir_orden_marcador"):
		# Le pasamos la orden, el tiempo, y AHORA TAMBIÉN el centro exacto del marcador
		body.recibir_orden_marcador(orden, tiempo_de_espera, global_position.x)
		
func _on_body_exited(body):
	# Si la orden es 5 (Subir) o 6 (Bajar), le avisamos que ya salió del área de la escalera
	if orden == 5 or orden == 6:
		if body.is_in_group("enemigo") and body.has_method("soltar_escalera"):
			body.soltar_escalera()
