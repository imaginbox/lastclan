shader_type spatial;

// Shader de terrain : génère un motif naturel différent par zone (herbe, sable,
// forêt, eau) avec des transitions douces entre biomes. Calculé sur GPU donc
// haute résolution, net et non pixelisé. Déterministe (même uniforms => même
// rendu pour tous les joueurs).

uniform vec3 u_desert_center = vec3(90.0, 0.0, 0.0);
uniform float u_desert_r = 60.0;
uniform vec3 u_forest_center = vec3(-90.0, 0.0, 0.0);
uniform float u_forest_r = 60.0;
uniform int u_segment_count = 0;
uniform vec4 u_river[32];         // chaque segment = (x1, z1, x2, z2)
uniform float u_river_width[32];
uniform float u_half = 200.0;     // demi-taille du sol (400x400)

const float ZONE_FALL = 16.0;
const float RIVER_FALL = 6.0;

// ---- bruit de valeur 2D ----
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i + vec2(0.0, 0.0));
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.0;
		a *= 0.5;
	}
	return v;
}

// ---- géométrie ----
float dist_seg(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	vec2 ap = p - a;
	float t = clamp(dot(ap, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	return length(ap - ab * t);
}
float smooth_zone(float d, float r) {
	float t = clamp((r + ZONE_FALL - d) / ZONE_FALL, 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}
float smooth_river(vec2 pos) {
	float best = 1e9;
	float best_w = 6.0;
	for (int i = 0; i < 32; i++) {
		if (i >= u_segment_count)
			break;
		vec4 s = u_river[i];
		float d = dist_seg(pos, s.xy, s.zw);
		if (d < best) {
			best = d;
			best_w = u_river_width[i];
		}
	}
	if (best > 1e8)
		return 0.0;
	float t = clamp((best - best_w + RIVER_FALL) / RIVER_FALL, 0.0, 1.0);
	return 1.0 - t * t * (3.0 - 2.0 * t);
}

// ---- motifs naturels par zone ----
vec3 grass_tex(vec2 p) {
	vec3 base = vec3(0.42, 0.66, 0.30);
	float patch = fbm(p * 1.6 + 7.0);    // grandes taches claires/sombres
	float patch2 = fbm(p * 4.5 + 19.0);  // taches moyennes
	float blade = fbm(p * 13.0 + 13.0);  // fin détail herbe
	float shade = (patch - 0.5) * 0.30 + (patch2 - 0.5) * 0.14;
	vec3 col = base * (1.0 + shade);
	col += vec3(0.05, 0.07, 0.0) * (blade - 0.5);
	return max(col, vec3(0.0));
}
vec3 desert_tex(vec2 p) {
	vec3 base = vec3(0.80, 0.71, 0.46);
	float grain = fbm(p * 7.0 + 3.0);    // grain de sable fin
	float dune = fbm(p * 1.1 + 17.0);    // grandes dunes douces
	float shade = (grain - 0.5) * 0.20 + (dune - 0.5) * 0.18;
	return max(base * (1.0 + shade), vec3(0.0));
}
vec3 forest_tex(vec2 p) {
	vec3 base = vec3(0.30, 0.52, 0.24);
	float patch = fbm(p * 1.8 + 5.0);    // sous-bois en touffes
	float patch2 = fbm(p * 5.0 + 23.0);
	float shade = (patch - 0.5) * 0.38 + (patch2 - 0.5) * 0.16;
	return max(base * (1.0 + shade), vec3(0.0));
}
vec3 water_tex(vec2 p) {
	vec3 base = vec3(0.20, 0.50, 0.85);
	float wave = fbm(p * 1.6 + 11.0);    // reflets ondulés
	return max(base * (1.0 + (wave - 0.5) * 0.16), vec3(0.0));
}

void fragment() {
	vec2 pos = (UV - 0.5) * 2.0 * u_half;

	// poids des biomes (transitions douces, pas de bord dur)
	float w_desert = smooth_zone(distance(pos, u_desert_center.xz), u_desert_r);
	float w_forest = smooth_zone(distance(pos, u_forest_center.xz), u_forest_r);
	float w_water = smooth_river(pos);
	float total = w_desert + w_forest + w_water;
	float w_grass = max(0.0, 1.0 - total);

	// mélange des motifs par zone
	vec3 col = grass_tex(pos) * w_grass
			 + desert_tex(pos) * w_desert
			 + forest_tex(pos) * w_forest
			 + water_tex(pos) * w_water;

	ALBEDO = col;
}
