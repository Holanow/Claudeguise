shader_type canvas_item;
render_mode blend_add;

// Draws the sector the action actually hits: `half_arc_radians` either side of
// +X, out to the full radius of the quad. The League guide's rule is that an
// effect must represent its own hitbox, and here the hitbox IS this sector.
uniform vec4 edge_colour : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform vec4 core_colour : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float half_arc_radians = 1.134;
// The leading edge sweeps 0 -> 1 across the arc, so it reads as a swing
// rather than a shape switching on.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float inner = 0.35;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	if (r > 1.0 || r < inner) { discard; }

	float a = atan(p.y, p.x);
	if (abs(a) > half_arc_radians) { discard; }

	// Where this fragment sits along the swing, 0 at one edge, 1 at the other.
	float along = (a + half_arc_radians) / (2.0 * half_arc_radians);
	// Trailing wedge behind the leading edge; nothing ahead of it yet.
	float behind = progress - along;
	if (behind < 0.0) { discard; }
	float tail = smoothstep(0.55, 0.0, behind);

	// Thin band hugging the outer reach, so the arc reads as a blade path and
	// not as a filled pie.
	float band = smoothstep(inner, 1.0, r);
	band *= smoothstep(1.0, 0.82, r);

	float edge_soft = smoothstep(half_arc_radians, half_arc_radians * 0.75, abs(a));
	float body = band * tail * edge_soft;
	// The leading edge itself is the bright part; the trail is dimmer.
	float lead = smoothstep(0.12, 0.0, behind) * band;

	vec3 col = mix(edge_colour.rgb, core_colour.rgb, clamp(lead, 0.0, 1.0));
	COLOR = vec4(col, clamp(body * 0.85 + lead, 0.0, 1.0) * fade);
}
