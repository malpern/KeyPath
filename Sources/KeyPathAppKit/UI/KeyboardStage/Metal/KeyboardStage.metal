#include <metal_stdlib>
using namespace metal;

struct KeyboardStageInstance {
    float4 geometry;      // center.xy and size.zw in normalized device coordinates
    float4 fillColor;
    float4 accentColor;
    float4 glowColor;
    float4 parameters;    // pressure, glow, opacity, border strength
    float4 treatment;     // rotation, corner ratio, shadow margin in pixels, reserved
    float4 lighting;      // illumination, transient glow, shadow strength, legend opacity
};

struct KeyboardStageUniforms {
    float2 viewportSize;
    float2 padding;
};

struct KeyboardStageVertexOut {
    float4 position [[position]];
    float2 localPixels;
    float2 halfSizePixels;
    float4 fillColor;
    float4 accentColor;
    float4 glowColor;
    float4 parameters;
    float4 lighting;
    float cornerRadiusPixels;
};

vertex KeyboardStageVertexOut keypath_keyboard_stage_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant KeyboardStageInstance *instances [[buffer(0)]],
    constant KeyboardStageUniforms &uniforms [[buffer(1)]]
) {
    constexpr float2 corners[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2(-1.0,  1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0),
    };

    KeyboardStageInstance instance = instances[instanceID];
    float2 halfSizePixels = instance.geometry.zw * uniforms.viewportSize * 0.25;
    float margin = instance.treatment.z;
    float2 localPixels = corners[vertexID] * (halfSizePixels + margin);

    float angle = instance.treatment.x;
    float sine = sin(angle);
    float cosine = cos(angle);
    float2 rotatedPixels = float2(
        localPixels.x * cosine - localPixels.y * sine,
        localPixels.x * sine + localPixels.y * cosine
    );
    float2 ndcOffset = float2(
        rotatedPixels.x * 2.0 / uniforms.viewportSize.x,
        -rotatedPixels.y * 2.0 / uniforms.viewportSize.y
    );

    KeyboardStageVertexOut output;
    output.position = float4(instance.geometry.xy + ndcOffset, 0.0, 1.0);
    output.localPixels = localPixels;
    output.halfSizePixels = halfSizePixels;
    output.fillColor = instance.fillColor;
    output.accentColor = instance.accentColor;
    output.glowColor = instance.glowColor;
    output.parameters = instance.parameters;
    output.lighting = instance.lighting;
    output.cornerRadiusPixels = min(halfSizePixels.x, halfSizePixels.y) * instance.treatment.y;
    return output;
}

static float keypath_rounded_rect_distance(
    float2 point,
    float2 halfSize,
    float radius
) {
    float2 offset = abs(point) - halfSize + radius;
    return length(max(offset, float2(0.0)))
        + min(max(offset.x, offset.y), 0.0)
        - radius;
}

fragment float4 keypath_keyboard_stage_fragment(KeyboardStageVertexOut input [[stage_in]]) {
    float pressure = saturate(input.parameters.x);
    float glow = saturate(input.parameters.y);
    float opacity = saturate(input.parameters.z);
    float borderStrength = saturate(input.parameters.w);
    float illumination = saturate(input.lighting.x);
    float transientGlow = saturate(input.lighting.y);
    float shadowStrength = max(1.0, input.lighting.z);

    float distance = keypath_rounded_rect_distance(
        input.localPixels,
        input.halfSizePixels,
        input.cornerRadiusPixels
    );
    float antialiasWidth = max(0.75, fwidth(distance));
    float surfaceAlpha = 1.0 - smoothstep(-antialiasWidth, antialiasWidth, distance);

    float contactShadowDistance = keypath_rounded_rect_distance(
        input.localPixels - float2(0.0, mix(1.8, 0.8, pressure)),
        input.halfSizePixels,
        input.cornerRadiusPixels
    );
    float contactShadowAlpha = (1.0 - smoothstep(-0.5, 3.0, contactShadowDistance))
        * mix(0.10, 0.06, pressure);
    float softShadowDistance = keypath_rounded_rect_distance(
        input.localPixels - float2(0.0, mix(5.0, 1.8, pressure)),
        input.halfSizePixels,
        input.cornerRadiusPixels
    );
    float softShadowAlpha = (1.0 - smoothstep(-1.0, 10.0, softShadowDistance))
        * mix(0.18, 0.10, pressure);
    float shadowAlpha = contactShadowAlpha
        + softShadowAlpha * (1.0 - contactShadowAlpha);
    shadowAlpha = saturate(shadowAlpha * shadowStrength);

    float outsideDistance = max(distance, 0.0);
    float roleGlowAlpha = exp(-outsideDistance * 0.18) * glow * 0.56;
    roleGlowAlpha *= 1.0 - surfaceAlpha;
    float entranceGlowAlpha = exp(-outsideDistance * 0.13) * transientGlow * 0.42;
    entranceGlowAlpha *= 1.0 - surfaceAlpha;
    float glowAlpha = roleGlowAlpha
        + entranceGlowAlpha * (1.0 - roleGlowAlpha);

    float verticalPosition = saturate(
        input.localPixels.y / max(1.0, input.halfSizePixels.y) * 0.5 + 0.5
    );
    float3 surfaceColor = input.fillColor.rgb * mix(1.004, 0.990, verticalPosition);
    surfaceColor *= mix(1.0, 0.94, pressure);
    float3 unlitSurface = mix(
        float3(0.009, 0.012, 0.018),
        input.fillColor.rgb * 0.040,
        0.25
    );
    surfaceColor = mix(unlitSurface, surfaceColor, illumination);

    float edge = smoothstep(-2.2, -0.15, distance) * surfaceAlpha;
    float edgeIllumination = mix(0.16, 1.0, illumination) + transientGlow * 0.24;
    surfaceColor = mix(
        surfaceColor,
        input.accentColor.rgb,
        edge * borderStrength * 0.72 * edgeIllumination
    );

    float underAlpha = max(shadowAlpha, glowAlpha);
    float3 shadowColor = mix(
        float3(0.011, 0.015, 0.024),
        float3(0.045, 0.040, 0.036),
        illumination
    );
    float3 entranceGlowColor = mix(
        input.glowColor.rgb,
        float3(0.36, 0.52, 0.78),
        0.32
    );
    float glowWeight = roleGlowAlpha + entranceGlowAlpha;
    float3 resolvedGlowColor = (
        input.glowColor.rgb * roleGlowAlpha
        + entranceGlowColor * entranceGlowAlpha
    ) / max(0.001, glowWeight);
    float3 underColor = mix(
        shadowColor,
        resolvedGlowColor,
        glowAlpha / max(0.001, shadowAlpha + glowAlpha)
    );
    float finalAlpha = surfaceAlpha + underAlpha * (1.0 - surfaceAlpha);
    float3 finalColor = (
        surfaceColor * surfaceAlpha
        + underColor * underAlpha * (1.0 - surfaceAlpha)
    ) / max(0.001, finalAlpha);

    return float4(finalColor, finalAlpha * opacity);
}
