shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 silhouette_color : source_color = vec4(0.25, 0.65, 1.0, 1.0);
uniform float emphasis = 0.0;
uniform bool active = true;
uniform vec3 actor_center = vec3(0.0);

void fragment() {
	float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc.z = depth * 2.0 - 1.0;
	#endif
	vec4 surface = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float surface_distance = -surface.z / surface.w;
	float unit_distance = -VERTEX.z;
	// Ignore tiny differences on the actor's own surface. Reveal only blocked pixels.
	float blocked = smoothstep(0.10, 0.20, unit_distance - surface_distance);
	// The foreground must also lie in front of the actor's body envelope.
	// This rejects arms/weapon/torso occluding one another in the same actor.
	float center_distance = -(VIEW_MATRIX * vec4(actor_center, 1.0)).z;
	blocked *= 1.0 - smoothstep(center_distance - 0.85, center_distance - 0.70, surface_distance);
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	ALBEDO = mix(silhouette_color.rgb, vec3(1.0), emphasis * 0.30);
	ALPHA = active ? blocked * (0.24 + rim * 0.24 + emphasis * 0.18) : 0.0;
}
