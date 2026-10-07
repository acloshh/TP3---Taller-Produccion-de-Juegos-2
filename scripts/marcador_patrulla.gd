extends Area2D

# Creamos un menú desplegable en el Inspector para elegir la acción
enum Accion { DAR_VUELTA, ESPERAR_Y_SEGUIR, ESPERAR_Y_DAR_VUELTA }
@export var tipo_accion: Accion = Accion.DAR_VUELTA
@export var tiempo_espera: float = 2.0
func _ready():
	# El marcador se oculta solo al darle Play para que el jugador no lo vea
	hide()
	# Conectamos la señal física
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	# Si el que chocó es un enemigo, le pasamos la orden
	if body.is_in_group("enemigo") and body.has_method("ejecutar_marcador"):
		body.ejecutar_marcador(tipo_accion, tiempo_espera)
