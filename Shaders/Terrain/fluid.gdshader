shader_type canvas_item;

// Issue 760: one surface for both fluids. Water is bright, quick and wide;
// blood is dark, slow and tight, and the difference is these four uniforms.
uniform vec4 tint : source_color = vec4(0.2, 0.5, 0.8, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.45;
uniform float speed = 1.0;
uniform float ripple_scale = 0.055;

// Arena-local pixels, so the surface is continuous across the cells a pool is
// painted in rather than restarting inside every one of them.
varying vec2 world;

void vertex() {
	world = VERTEX;
}

float wave(vec2 p, vec2 dir, float freq, float rate) {
	return sin(dot(p, dir) * freq + TIME * rate);
}

void fragment() {
	// Warped before it is waved, or three straight sine bands read as diagonal
	// stripes -- which is already the grammar a HAZARD cell speaks in.
	vec2 p = world * ripple_scale;
	p += vec2(sin(p.y * 1.7 + TIME * 0.40 * speed),
		cos(p.x * 1.9 - TIME * 0.33 * speed)) * 0.7;

	// Three frequencies, not one: a slow swell the eye reads as the pool
	// moving, a cross ripple that gives it a surface, and a fine chop on top.
	float h = wave(p, vec2(0.94, 0.34), 1.0, 0.55 * speed) * 0.50
		+ wave(p, vec2(-0.42, 0.91), 2.7, 1.60 * speed) * 0.34
		+ wave(p, vec2(0.36, 0.93), 6.1, 2.90 * speed) * 0.16;

	// Value before colour: the body darkens into the troughs, and a much
	// smaller, much brighter crest is the thing the eye lands on.
	vec3 body = tint.rgb * (0.82 + 0.24 * h);
	vec3 rgb = mix(body, mix(body, vec3(1.0), 0.4), smoothstep(0.80, 1.0, h));

	// COLOR carries which of the four sides face other ground -- left, right,
	// top, bottom -- so only a pool's outline softens and the seams between
	// the cells inside it stay flush. It fades inward and never outward: the
	// cells the simulation reads are the widest this can draw.
	float open = max(max(COLOR.r * (1.0 - UV.x), COLOR.g * UV.x),
		max(COLOR.b * (1.0 - UV.y), COLOR.a * UV.y));
	float edge = 1.0 - smoothstep(0.66, 1.0, open + h * 0.12);

	COLOR = vec4(rgb, base_alpha * (0.88 + 0.12 * h) * edge);
}
