// grass.gdshader
// Shader de sol en herbe "anti-motif répétitif" (anti-tiling).
// La texture est échantillonnée trois fois à des échelles et orientations
// différentes, puis mélangée par un bruit à grande échelle. Cela détruit les
// lignes de répétition visibles quand une petite tuile recouvre un grand terrain.

shader_type spatial;
render_mode blend_mix, diffuse_burley, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear, repeat_enable;
uniform float scale_tile = 20.0;   // taille globale des tuiles
uniform float color_variation = 0.18; // force de la variation de couleur
uniform float brightness = 1.05;

// Bruit simple de type valeur (basé sur des coordonnées spatiales), doux et
// continu, pour moduler la mélange entre les 3 échantillons sans artefacts.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm_noise(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int k = 0; k < 5; k++) {
		v += noise(p) * amp;
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = FRAGCOORD.xy; // coordonnées écran continues → bruit stable à grande échelle

	// Trois échantillons à échelles/orientations différentes pour casser le tiling.
	vec2 uv_a = UV * scale_tile;
	vec2 uv_b = UV * (scale_tile * 1.7) + vec2(13.7, 7.3);
	vec2 uv_c = UV * (scale_tile * 0.63) + vec2(3.1, -9.2);

	vec3 col_a = texture(albedo_tex, uv_a).rgb;
	vec3 col_b = texture(albedo_tex, uv_b).rgb;
	vec3 col_c = texture(albedo_tex, uv_c).rgb;

	// Poids qui dépendent du bruit : mélange organique, jamais vraiment aligné.
	float noise_val = fbm_noise(uv * 40.0 + vec2(50.0, 25.0));
	float w_a = 0.5 + 0.4 * noise_val;
	float w_b = 0.5 - 0.3 * noise_val;
	float w_c = 0.35 + 0.25 * fbm_noise(uv * 0.6 + vec2(11.0, 17.0));
	float w_sum = w_a + w_b + w_c;

	vec3 color = (col_a * w_a + col_b * w_b + col_c * w_c) / w_sum;

	// Variation de luminosité à grande échelle pour briser encore la monotonie.
	float shade = fbm_noise(uv * 12.0 + vec2(80.0, -40.0));
	color *= 1.0 + (shade - 0.5) * color_variation;
	color *= brightness;

	ALBEDO = color;
	ROUGHNESS = 1.0;
}
