extends StaticBody2D

func _ready():
	add_to_group("enemigo")

# Lo llama el cuchillo
func recibir_dano():
	owner.caer_puente()

# Lo llama la flecha
func recibir_flechazo(_tipo_flecha):
	owner.caer_puente()
