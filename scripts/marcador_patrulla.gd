extends Area2D

@export_enum("Solo Dar Vuelta", "Frenar y Seguir", "Frenar y Dar Vuelta", "Saltar Obstaculo", "Caer al Vacio") var orden: int = 0
@export var tiempo_de_espera: float = 2.0

func _ready():
	# Conectamos la señal por código para que no tengas que hacerlo a mano
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.is_in_group("enemigo") and body.has_method("recibir_orden_marcador"):
		body.recibir_orden_marcador(orden, tiempo_de_espera)
