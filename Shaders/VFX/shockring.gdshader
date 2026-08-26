shader_type canvas_item;
render_mode blend_add;

uniform vec4 ring_colour : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float thickness = 0.20;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	// Thins and dims as it expands, which is what reads as a shockwave rather
	// than a growing donut.
	float t = thickness * (1.0 - progress * 0.75);
	COLOR = vec4(ring_colour.rgb,
		smoothstep(t, 0.0, abs(r - progress)) * (1.0 - progress * 0.85));
}
