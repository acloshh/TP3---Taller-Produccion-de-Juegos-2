shader_type canvas_item;

// Qué tanta curva querés (1.0 = plano, 1.1 = curva normal, 1.2 = muy curvo)
uniform float BarrelPower = 1.0;

// EL SECRETO DEL PIXEL ART: filter_nearest evita que los píxeles se vean borrosos
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

vec2 distort(vec2 p) 
{
	float theta = atan(p.y, p.x);
	float radius = pow(length(p), BarrelPower);
	
	p.x = radius * cos(theta);
	p.y = radius * sin(theta);
	
	return 0.5 * (p + vec2(1.0, 1.0));
}

void fragment()
{
	// Convertimos las coordenadas para que el centro de la pantalla sea (0,0)
	vec2 xy = SCREEN_UV * 2.0;
	xy.x -= 1.0;
	xy.y -= 1.0;
	
	// Aplicamos la curvatura si estamos dentro del rango
	float d = length(xy);
	if(d < 1.5){
		xy = distort(xy);
	}
	else{
		xy = SCREEN_UV;
	}
	
	// Leemos el color exacto de la pantalla deformada, sin mezclar nada
	COLOR = texture(SCREEN_TEXTURE, xy);
}