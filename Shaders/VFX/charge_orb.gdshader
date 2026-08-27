shader_type canvas_item;
render_mode blend_add;

// Geometry that is a function of live state, which is the one thing CLAUDE.md
// says may still be drawn rather than baked: `charge` moves every frame.
uniform vec4 inner_colour : source_color = vec4(1.0, 0.95, 0.7, 1.0);
uniform vec4 outer_colour : source_color = vec4(1.0, 0.35, 0.06, 1.0);
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float turbulence = 5.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
	           mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;
	// Sampled in polar space so it reads as gathering rather than drifting.
	float swirl = noise(vec2(atan(p.y, p.x) * turbulence + TIME * 3.0, r * 6.0 - TIME * 4.0));
	float radius = mix(0.15, 1.0, charge);
	float body = smoothstep(radius, radius * 0.25, r);
	vec3 col = mix(outer_colour.rgb, inner_colour.rgb, pow(1.0 - r / max(radius, 0.001), 2.0));
	COLOR = vec4(col, clamp(body * (0.65 + 0.35 * swirl) * charge, 0.0, 1.0));
}
