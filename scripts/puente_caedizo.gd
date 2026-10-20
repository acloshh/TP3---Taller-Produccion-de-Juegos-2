extends Node2D

@onready var pivote = $Pivote
@onready var contrapeso = $Contrapeso

var puente_caido = false

func caer_puente():
	if puente_caido: return
	puente_caido = true
	
	var tween = create_tween()
	
	# EASE_IN hace que acelere hacia el final (gravedad pura).
	# TRANS_EXPO o TRANS_QUAD le dan esa curva de caída pesada.
	tween.tween_property(pivote, "rotation_degrees", 0.0, 1.5)\
		.set_trans(Tween.TRANS_EXPO)\
		.set_ease(Tween.EASE_IN)
		
	# Destruimos el contrapeso para que desaparezca la soga
	contrapeso.queue_free()	
