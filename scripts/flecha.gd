extends Area2D

var velocity = Vector2.ZERO
var gravedad = ProjectSettings.get_setting("physics/2d/default_gravity")
var tipo = "letal" 
@onready var anim = $AnimatedSprite2D

func _ready():
	# Apenas se dispara, reproduce la animación correspondiente
	anim.play(tipo)
	
	# Dale el impulso inicial si le pusiste velocidad fija, sino esto lo controla el arco
	rotation = velocity.angle()

func _physics_process(delta):
	velocity.y += gravedad * delta
	position += velocity * delta
	rotation = velocity.angle()

func _on_body_entered(body):
	if body.is_in_group("enemigo") and body.has_method("recibir_flechazo"):
		body.recibir_flechazo(tipo)
	
	if not body.is_in_group("jugador"):
		queue_free()
