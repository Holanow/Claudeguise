shader_type canvas_item;
render_mode blend_add;

uniform vec4 core_colour : source_color = vec4(1.0, 0.98, 0.85, 1.0);
uniform vec4 edge_colour : source_color = vec4(1.0, 0.30, 0.05, 1.0);
uniform float extend : hint_range(0.0, 1.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float width_scale = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
	           mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; }
	return v;
}

void fragment() {
	// UV.x runs caster to target, UV.y across the beam.
	float along = UV.x;
	float across = abs(UV.y - 0.5) * 2.0;
	if (along > extend) { discard; }

	float turb = fbm(vec2(along * 9.0 - TIME * 7.0, UV.y * 5.0 + TIME * 1.5));
	float taper = sin(along * 3.14159) * 0.55 + 0.45;
	float w = clamp(taper * width_scale * (0.55 + 0.75 * turb), 0.05, 1.0);
	float body = smoothstep(w, w * 0.15, across);
	float core = smoothstep(w * 0.42, 0.0, across);

	// Masked by the beam's own width; unmasked it draws a slash across the room.
	float head = smoothstep(0.10, 0.0, abs(along - extend))
		* (1.0 - step(1.0, extend)) * smoothstep(w, w * 0.15, across);
	// The root sits on the caster's chest and should read as the source.
	float root = smoothstep(0.20, 0.0, along) * smoothstep(w * 1.5, 0.0, across);

	vec3 col = mix(edge_colour.rgb, core_colour.rgb, clamp(core + head + root, 0.0, 1.0));
	COLOR = vec4(col, clamp(body + core * 0.9 + head + root * 0.75, 0.0, 1.0) * fade);
}
