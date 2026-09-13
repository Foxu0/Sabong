shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled;

uniform sampler2D texture_albedo : source_color;
uniform float corner_radius : hint_range(0.0, 0.5) = 0.08;
uniform float aspect_ratio = 1.4;

void fragment() {
    vec2 uv = UV;
    vec2 aspect_correct = vec2(1.0, aspect_ratio);
    vec2 halfSize = vec2(0.5) * aspect_correct;
    vec2 pos = abs((uv - vec2(0.5)) * aspect_correct) - (halfSize - vec2(corner_radius));
    float dist = length(max(pos, 0.0)) - corner_radius;
    float corner_mask = 1.0 - smoothstep(0.0, 0.005, dist);

    vec4 tex = texture(texture_albedo, uv);

    ALBEDO = tex.rgb;
    ALPHA = corner_mask * tex.a;
}