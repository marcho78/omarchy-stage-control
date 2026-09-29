// Liquid Glass: a rounded pane that refracts what is behind it.
//
// The backdrop (Mission Control's wallpaper layer, shared by every pane) is
// sampled through the pane: frosted by reading a blurrier mip level, bent
// inward near the rim like the edge of a thick lens, split slightly by color
// right at the rim, tinted, and lit by a specular rim that is brightest where
// the edge faces the light (top left) with a dimmer kick on the far side.
//
// Build: shaders/build (Qt's qsb). The .qsb next to this file is what loads.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;      // pane size in pixels
    float radius;       // corner radius in pixels
    float bevel;        // width of the bending rim, pixels
    float refraction;   // how far the rim bends the backdrop, pixels
    float frost;        // mip level to read the backdrop at (0 = clear)
    float rim;          // specular strength, 0..1
    float flip;         // 1 when the backdrop texture is stored bottom-up
    vec4 area;          // the pane's rect within the backdrop, 0..1 (x, y, w, h)
    vec4 tint;          // straight-alpha color laid over the glass
    vec4 fill;          // straight-alpha color for hover and selection
};

layout(binding = 1) uniform sampler2D backdrop;

float roundBox(vec2 p, vec2 half_size, float r) {
    vec2 q = abs(p) - half_size + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec2 backdropUv(vec2 local) {
    vec2 uv = area.xy + local * area.zw;
    if (flip > 0.5) uv.y = 1.0 - uv.y;
    return uv;
}

void main() {
    vec2 half_size = itemSize * 0.5;
    vec2 p = qt_TexCoord0 * itemSize - half_size;
    float r = min(radius, min(half_size.x, half_size.y));
    float d = roundBox(p, half_size, r);          // negative inside
    float coverage = clamp(0.5 - d, 0.0, 1.0);
    if (coverage <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Outward normal of the rounded rect.
    vec2 e = vec2(0.5, 0.0);
    vec2 n = vec2(roundBox(p + e.xy, half_size, r) - roundBox(p - e.xy, half_size, r),
                  roundBox(p + e.yx, half_size, r) - roundBox(p - e.yx, half_size, r));
    float len = length(n);
    n = len > 1e-4 ? n / len : vec2(0.0);

    // 1 at the rim, 0 once `bevel` pixels in.
    float edge = 1.0 - clamp(-d / max(bevel, 0.001), 0.0, 1.0);
    float bend = edge * edge * edge;

    // The rim pulls its samples inward: what's under the pane looks magnified
    // toward the edges, like looking through a lens.
    vec2 local = qt_TexCoord0 - n * refraction * bend / itemSize;
    vec2 split = n * bend * 1.5 / itemSize;
    vec3 color;
    color.r = textureLod(backdrop, backdropUv(local + split), frost).r;
    color.g = textureLod(backdrop, backdropUv(local), frost).g;
    color.b = textureLod(backdrop, backdropUv(local - split), frost).b;

    color = mix(color, tint.rgb, tint.a);
    color = mix(color, fill.rgb, fill.a);

    // Specular rim: a hairline catching the light from the top left, a
    // softer glow inside it, and a dimmer highlight on the opposite edge.
    vec2 light = normalize(vec2(-0.55, -0.85));
    float facing = dot(n, light);
    float hairline = clamp(1.0 - (-d) / 1.4, 0.0, 1.0);
    float glow = edge * edge;
    float spec = hairline * (0.10 + 0.60 * max(facing, 0.0) + 0.30 * max(-facing, 0.0))
               + glow * 0.12 * max(facing, 0.0);
    color += vec3(spec * rim);

    // A touch darker toward the bottom, for depth.
    color *= 1.0 - 0.05 * qt_TexCoord0.y;

    fragColor = vec4(color, 1.0) * coverage * qt_Opacity;
}
