shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform sampler2D reveal_map : repeat_disable, filter_linear;
uniform vec3 fog_color : source_color = vec3(0.72, 0.76, 0.82);
uniform float world_half : hint_range(1.0, 200.0) = 30.0;
uniform float fog_opacity : hint_range(0.0, 1.0) = 0.8;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (v_world.xz + vec2(world_half)) / (world_half * 2.0);
	float reveal = texture(reveal_map, uv).r;
	// Courbe douce : le brouillard s'épaissit progressivement, sans ligne
	// franche, enveloppant l'unité/la ville de tous les côtés.
	float alpha = fog_opacity * pow(1.0 - reveal, 1.3);
	ALBEDO = fog_color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}