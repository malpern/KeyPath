#include <metal_stdlib>
using namespace metal;

struct KeyboardStageInstance {
    float4 geometry;      // center.xy and size.zw in normalized device coordinates
    float4 fillColor;
    float4 accentColor;
    float4 glowColor;
    float4 parameters;    // pressure, glow, opacity, border strength
    float4 treatment;     // rotation, corner ratio, shadow margin in pixels, reserved
    float4 lighting;      // illumination, transient glow, shadow strength, interaction level
};

struct KeyboardStageUniforms {
    float2 viewportSize;
    float2 entrance;      // raw entrance progress, Reduce Motion flag
    float2 windowX;       // stage origin and width in normalized window coordinates
    float4 cinematicLighting; // current front, feather, vertical skew, reserved
    // Runtime lighting tuning (see KeyboardStageTuning.swift for the shipped
    // defaults and the developer harness that overrides them).
    float4 tuningA;       // graze deck ambient/diffuse, graze key ambient/diffuse
    float4 tuningB;       // graze mask start, rim peak, rim power, emphasis rim floor
    float4 tuningC;       // well expansion, contact strength, cast strength, backlight
    float4 tuningD;       // legend emission min/max, legend base min/max
};

struct KeyboardStageLegendInstance {
    float4 geometry;      // center.xy and size.zw in normalized device coordinates
    float4 uvRect;        // atlas origin.xy and size.zw in normalized texture coordinates
    float4 settledColor;  // linear-sRGB legend color and alpha
    float4 parameters;    // opacity, entrance emission, role emission, reserved
};

struct KeyboardStagePostUniforms {
    float4 sourceAndBloomSize;   // source width/height, bloom width/height
    float4 entranceAndDirection; // progress, Reduce Motion flag, light direction.xy
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
    float2 stageUV;
    float materialKind;
};

struct KeyboardStageLegendVertexOut {
    float4 position [[position]];
    float2 atlasUV;
    float2 stageUV;
    float4 settledColor;
    float4 parameters;
};

struct KeyboardStageFullscreenOut {
    float4 position [[position]];
    float2 uv;
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
    float localX = output.position.x * 0.5 + 0.5;
    output.stageUV = float2(
        uniforms.windowX.x + localX * uniforms.windowX.y,
        0.5 - output.position.y * 0.5
    );
    output.materialKind = instance.treatment.w;
    return output;
}

vertex KeyboardStageLegendVertexOut keypath_keyboard_legend_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant KeyboardStageLegendInstance *instances [[buffer(0)]],
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

    KeyboardStageLegendInstance instance = instances[instanceID];
    float2 corner = corners[vertexID];
    float2 position = instance.geometry.xy + corner * instance.geometry.zw * 0.5;
    float2 unitUV = float2(corner.x * 0.5 + 0.5, 0.5 - corner.y * 0.5);

    KeyboardStageLegendVertexOut output;
    output.position = float4(position, 0.0, 1.0);
    output.atlasUV = instance.uvRect.xy + unitUV * instance.uvRect.zw;
    float localX = position.x * 0.5 + 0.5;
    output.stageUV = float2(
        uniforms.windowX.x + localX * uniforms.windowX.y,
        0.5 - position.y * 0.5
    );
    output.settledColor = instance.settledColor;
    output.parameters = instance.parameters;
    return output;
}

vertex KeyboardStageFullscreenOut keypath_fullscreen_vertex(
    uint vertexID [[vertex_id]]
) {
    constexpr float2 coordinates[3] = {
        float2(0.0, 0.0),
        float2(2.0, 0.0),
        float2(0.0, 2.0),
    };

    KeyboardStageFullscreenOut output;
    output.uv = coordinates[vertexID];
    output.position = float4(
        output.uv.x * 2.0 - 1.0,
        1.0 - output.uv.y * 2.0,
        0.0,
        1.0
    );
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

static float keypath_critically_damped_progress(float rawProgress) {
    float progress = saturate(rawProgress);
    if (progress <= 0.0 || progress >= 1.0) {
        return progress;
    }

    constexpr float response = 8.0;
    float value = 1.0 - (1.0 + response * progress) * exp(-response * progress);
    float settledValue = 1.0 - (1.0 + response) * exp(-response);
    return saturate(value / settledValue);
}

static float keypath_cinematic_exposure(
    float rawProgress,
    float2 normalizedPosition,
    bool reduceMotion,
    float4 cinematicLighting
) {
    if (reduceMotion) {
        return keypath_critically_damped_progress(rawProgress);
    }
    if (rawProgress <= 0.0) {
        return 0.0;
    }
    if (rawProgress >= 1.0) {
        return 1.0;
    }

    float2 position = saturate(normalizedPosition);
    float coordinate = position.x
        + (0.5 - position.y) * cinematicLighting.z;
    return smoothstep(
        cinematicLighting.x,
        cinematicLighting.x + cinematicLighting.y,
        coordinate
    );
}

static float keypath_hash(float2 point) {
    return fract(sin(dot(point, float2(12.9898, 78.233))) * 43758.5453);
}

static float keypath_value_noise(float2 point) {
    float2 cell = floor(point);
    float2 fraction = fract(point);
    float2 eased = fraction * fraction * (3.0 - 2.0 * fraction);
    float lowerLeft = keypath_hash(cell);
    float lowerRight = keypath_hash(cell + float2(1.0, 0.0));
    float upperLeft = keypath_hash(cell + float2(0.0, 1.0));
    float upperRight = keypath_hash(cell + float2(1.0, 1.0));
    return mix(
        mix(lowerLeft, lowerRight, eased.x),
        mix(upperLeft, upperRight, eased.x),
        eased.y
    );
}

static float keypath_area_shadow(
    float2 point,
    float2 halfSize,
    float radius,
    float2 castOffset,
    float softness
) {
    float2 perpendicular = normalize(float2(-castOffset.y, castOffset.x));
    float sampleSpread = max(0.75, softness * 0.34);
    constexpr float sampleWeights[5] = { 0.10, 0.23, 0.34, 0.23, 0.10 };
    constexpr float samplePositions[5] = { -1.0, -0.48, 0.0, 0.48, 1.0 };
    float shadow = 0.0;
    for (uint index = 0; index < 5; ++index) {
        float2 sampleOffset = castOffset
            + perpendicular * samplePositions[index] * sampleSpread;
        float distance = keypath_rounded_rect_distance(
            point - sampleOffset,
            halfSize,
            radius
        );
        shadow += (1.0 - smoothstep(-0.40, softness, distance))
            * sampleWeights[index];
    }
    return saturate(shadow);
}

static float keypath_ggx_distribution(float normalDotHalf, float roughness) {
    float alpha = max(0.04, roughness * roughness);
    float alphaSquared = alpha * alpha;
    float denominator = normalDotHalf * normalDotHalf * (alphaSquared - 1.0) + 1.0;
    return alphaSquared / max(0.0001, 3.14159265 * denominator * denominator);
}

static float keypath_smith_visibility(float normalDotView, float normalDotLight, float roughness) {
    float k = pow(roughness + 1.0, 2.0) * 0.125;
    float view = normalDotView / max(0.0001, normalDotView * (1.0 - k) + k);
    float light = normalDotLight / max(0.0001, normalDotLight * (1.0 - k) + k);
    return view * light;
}

static float3 keypath_fresnel_schlick(float cosine, float3 reflectance) {
    return reflectance + (1.0 - reflectance) * pow(1.0 - saturate(cosine), 5.0);
}

static float2 keypath_rounded_rect_gradient(
    float2 point,
    float2 halfSize,
    float radius
) {
    constexpr float epsilon = 0.75;
    float horizontal = keypath_rounded_rect_distance(
        point + float2(epsilon, 0.0),
        halfSize,
        radius
    ) - keypath_rounded_rect_distance(
        point - float2(epsilon, 0.0),
        halfSize,
        radius
    );
    float vertical = keypath_rounded_rect_distance(
        point + float2(0.0, epsilon),
        halfSize,
        radius
    ) - keypath_rounded_rect_distance(
        point - float2(0.0, epsilon),
        halfSize,
        radius
    );
    return normalize(float2(horizontal, vertical) + float2(0.0001));
}

fragment float4 keypath_keyboard_stage_fragment(
    KeyboardStageVertexOut input [[stage_in]],
    constant KeyboardStageUniforms &uniforms [[buffer(1)]]
) {
    float pressure = saturate(input.parameters.x);
    float glow = saturate(input.parameters.y);
    float opacity = saturate(input.parameters.z);
    float borderStrength = saturate(input.parameters.w);
    bool isDeck = input.materialKind < 0.5;
    bool isKey = input.materialKind >= 0.5 && input.materialKind < 1.5;
    // Chips are floating UI affordances (launcher/Rules capsules, tokens),
    // not keycaps: flatter edges, a soft top sheen, and an elevated shadow
    // instead of a seated key's bevel-and-well treatment.
    bool isChip = input.materialKind >= 1.5;
    float keyPress = isKey ? saturate(input.lighting.w) : 0.0;
    bool reduceMotion = uniforms.entrance.y > 0.5;
    float pixelExposure = keypath_cinematic_exposure(
        uniforms.entrance.x,
        input.stageUV,
        reduceMotion,
        uniforms.cinematicLighting
    );
    // The opening frame is a genuinely dark room. Mixing even a few percent
    // of the final near-white palette into linear light lifts the deck into a
    // gray card, so the spatial area-light exposure is the illumination.
    float illumination = pixelExposure;
    float transientGlow = saturate(input.lighting.y);
    float shadowStrength = max(1.0, input.lighting.z);

    float distance = keypath_rounded_rect_distance(
        input.localPixels,
        input.halfSizePixels,
        input.cornerRadiusPixels
    );
    float antialiasWidth = max(0.75, fwidth(distance));
    float surfaceAlpha = 1.0 - smoothstep(-antialiasWidth, antialiasWidth, distance);

    // The keycap floats above a recessed well. These masks are deliberately
    // separate: a dark cavity, a tight contact occlusion ring, and the exposed
    // strip of the backlight diffuser. Collapsing them into one blur makes the
    // keyboard read like flat rounded rectangles instead of physical hardware.
    float outsideDistance = max(distance, 0.0);
    // In the dark hold the wells widen and deepen so each cap visibly floats
    // above a recessed cavity like the reference photograph; the settled
    // light state keeps its original softer geometry.
    float wellDistance = keypath_rounded_rect_distance(
        input.localPixels,
        input.halfSizePixels
            + float2(isKey ? mix(uniforms.tuningC.x, 3.6, illumination) : 0.0),
        input.cornerRadiusPixels + (isKey ? mix(3.4, 2.2, illumination) : 0.0)
    );
    float wellMask = isKey
        ? (1.0 - smoothstep(-0.25, mix(2.1, 1.20, illumination), wellDistance))
            * (1.0 - surfaceAlpha)
        : 0.0;
    float contactOcclusion = isKey
        ? exp(-outsideDistance * mix(0.55, 0.92, illumination)) * wellMask
        : 0.0;
    float cavityOcclusion = isKey
        ? exp(-outsideDistance * mix(0.165, 0.24, illumination)) * wellMask
        : 0.0;
    float wellAlpha = saturate(
        contactOcclusion * mix(0.96, 0.38, illumination)
            + cavityOcclusion * mix(0.52, 0.08, illumination)
    );
    float skirtDistance = keypath_rounded_rect_distance(
        input.localPixels - float2(
            mix(0.45, 0.10, pressure),
            mix(2.45, 0.55, pressure)
        ),
        input.halfSizePixels + float2(isKey ? 2.15 : 0.0),
        input.cornerRadiusPixels + (isKey ? 1.05 : 0.0)
    );
    float skirtAlpha = isKey
        ? (1.0 - smoothstep(-0.35, 2.1, skirtDistance)) * (1.0 - surfaceAlpha)
        : 0.0;
    skirtAlpha *= mix(0.92, 0.52, illumination);

    float contactShadowAlpha = keypath_area_shadow(
        input.localPixels,
        input.halfSizePixels + float2(isKey ? 0.55 : 0.0),
        input.cornerRadiusPixels + (isKey ? 0.35 : 0.0),
        float2(
            mix(isDeck ? -0.3 : -0.65, -0.08, pressure),
            mix(isDeck ? 2.8 : 2.45, 0.58, pressure)
        ),
        isDeck ? 5.6 : 2.65
    ) * (1.0 - surfaceAlpha) * mix(isDeck ? 0.16 : 0.63, 0.10, pressure);
    float castShadowAlpha = keypath_area_shadow(
        input.localPixels,
        input.halfSizePixels,
        input.cornerRadiusPixels,
        float2(
            mix(isDeck ? -2.0 : (isChip ? -2.9 : -2.35), -0.35, pressure),
            mix(isDeck ? 10.5 : (isChip ? 12.5 : 8.6), 2.0, pressure)
        ),
        isDeck ? 18.0 : (isChip ? 16.0 : 10.5)
    ) * (1.0 - surfaceAlpha) * mix(isDeck ? 0.26 : (isChip ? 0.44 : 0.34), 0.09, pressure);
    if (isChip) {
        // Hovering above the deck: almost no tight contact, all soft cast.
        contactShadowAlpha *= 0.45;
    }
    contactShadowAlpha *= mix(uniforms.tuningC.y, 0.48, illumination);
    castShadowAlpha *= mix(uniforms.tuningC.z, 0.72, illumination);
    float shadowAlpha = contactShadowAlpha
        + castShadowAlpha * (1.0 - contactShadowAlpha);
    shadowAlpha = saturate(shadowAlpha * shadowStrength);

    // Backlight is an emissive plane under the cap, visible only where the
    // raised cap does not occlude its well. It escapes more strongly opposite
    // the area light and near corners, avoiding an even neon ring.
    float2 normalizedCapPosition = input.localPixels
        / max(input.halfSizePixels, float2(1.0));
    float2 radialDirection = normalize(normalizedCapPosition + float2(0.0001));
    float2 incomingLight = normalize(float2(0.88, -0.48));
    float edgeEscape = saturate(0.34 - dot(radialDirection, incomingLight) * 0.66);
    float cornerEscape = pow(saturate(max(abs(normalizedCapPosition.x), abs(normalizedCapPosition.y))), 3.0);
    float diffuserExposure = wellMask
        * saturate(0.010 + edgeEscape * 0.42 + cornerEscape * 0.08);
    float backlightStrength = isKey
        ? mix(uniforms.tuningC.w, 0.0, illumination) * (0.76 + transientGlow * 0.24)
        : 0.0;
    float diffuserBacklight = diffuserExposure * backlightStrength * 0.58;
    float tightBacklight = exp(-outsideDistance * 0.62)
        * diffuserExposure
        * backlightStrength
        * 0.22;
    float broadBacklight = exp(-outsideDistance * 0.14)
        * diffuserExposure
        * backlightStrength
        * 0.045;
    float instructionalEmphasis = max(
        glow,
        saturate((borderStrength - 0.60) * 5.0)
    );
    float roleGlowAlpha = exp(-outsideDistance * 0.34)
        * diffuserExposure
        * instructionalEmphasis
        * 0.31;
    float roleHaloAlpha = exp(-outsideDistance * 0.12)
        * edgeEscape
        * instructionalEmphasis
        * mix(0.095, 0.024, illumination)
        * (1.0 - surfaceAlpha);
    roleGlowAlpha = roleGlowAlpha
        + roleHaloAlpha * (1.0 - roleGlowAlpha);
    float pressGlowAlpha = exp(-outsideDistance * 0.46)
        * diffuserExposure
        * keyPress
        * mix(0.24, 0.08, illumination)
        * step(0.001, glow)
        * (1.0 - surfaceAlpha);
    roleGlowAlpha = roleGlowAlpha
        + pressGlowAlpha * (1.0 - roleGlowAlpha);
    float entranceGlowAlpha = diffuserBacklight + tightBacklight + broadBacklight;
    entranceGlowAlpha *= 1.0 - surfaceAlpha;
    float glowAlpha = roleGlowAlpha
        + entranceGlowAlpha * (1.0 - roleGlowAlpha);

    float bevelWidth = isDeck
        ? min(8.0, min(input.halfSizePixels.x, input.halfSizePixels.y) * 0.10)
        : (isChip
            ? min(3.0, min(input.halfSizePixels.x, input.halfSizePixels.y) * 0.12)
            : min(6.0, min(input.halfSizePixels.x, input.halfSizePixels.y) * 0.20));
    float bevel = smoothstep(-bevelWidth, -0.20, distance) * surfaceAlpha;
    float2 distanceGradient = keypath_rounded_rect_gradient(
        input.localPixels,
        input.halfSizePixels,
        input.cornerRadiusPixels
    );
    // The reference reads as one warm area light at the upper right: rims
    // catch only on light-facing edges and the far sides fall to black. In
    // the dark room every additive edge term follows this mask; the settled
    // light keeps the original even response.
    float2 rimLightDirection = normalize(float2(0.70, -0.62));
    float edgeFacing = saturate(dot(distanceGradient, rimLightDirection));
    float directionalRim = pow(edgeFacing, uniforms.tuningB.z);
    float rimDirectionality = mix(directionalRim * uniforms.tuningB.y, 1.0, illumination);
    float emphasisRimShape = mix(
        max(directionalRim, uniforms.tuningB.w),
        1.0,
        illumination
    );
    float bevelDepth = isDeck ? 0.22 : (isChip ? 0.30 : 0.72);
    float2 faceCoordinate = clamp(
        input.localPixels / max(input.halfSizePixels, float2(1.0)),
        float2(-1.0),
        float2(1.0)
    );
    float faceMask = isKey ? (1.0 - bevel) * surfaceAlpha : 0.0;
    float2 crownNormal = faceCoordinate * float2(0.055, 0.075) * faceMask;
    float3 normal = normalize(float3(
        distanceGradient.x * bevel * bevelDepth + crownNormal.x,
        distanceGradient.y * bevel * bevelDepth + crownNormal.y,
        1.0
    ));

    // Two octaves of low-amplitude height noise supply molded-plastic grain
    // and brushed aluminum microfacets. Deriving the normal in the shader keeps
    // the detail scale stable and avoids a visibly tiled photographic texture.
    float2 materialPixels = input.stageUV * uniforms.viewportSize;
    float microScale = isDeck ? 0.085 : 0.16;
    float2 microCoordinate = materialPixels * microScale;
    float microCenter = keypath_value_noise(microCoordinate);
    float microX = keypath_value_noise(microCoordinate + float2(0.55, 0.0)) - microCenter;
    float microY = keypath_value_noise(microCoordinate + float2(0.0, 0.55)) - microCenter;
    float brushedRidge = isDeck
        ? sin(materialPixels.y * 1.82 + keypath_value_noise(materialPixels * 0.012) * 4.0)
            * 0.0038
        : 0.0;
    float microNormalStrength = isDeck ? 0.026 : 0.014;
    normal = normalize(normal + float3(
        microX * microNormalStrength,
        microY * microNormalStrength + brushedRidge,
        0.0
    ));

    // A broad source moves right-to-left. Its specular front catches each
    // bevel before the diffuse exposure arrives, like a product-film area light.
    float lightFront = uniforms.cinematicLighting.x;
    float lightCoordinate = input.stageUV.x
        + (0.5 - input.stageUV.y) * uniforms.cinematicLighting.z;
    float grazingBand = reduceMotion
        ? 0.0
        : exp(-pow((lightCoordinate - lightFront) / 0.18, 2.0))
            * sin(saturate(uniforms.entrance.x) * 3.14159265);
    float3 lightDirection = normalize(float3(0.62, -0.28, 0.74));
    float diffuse = saturate(dot(normal, lightDirection));
    float normalDotView = saturate(normal.z);
    float normalDotLight = max(0.001, diffuse);
    float3 halfVector = normalize(lightDirection + float3(0.0, 0.0, 1.0));
    float normalDotHalf = saturate(dot(normal, halfVector));
    float viewDotHalf = saturate(halfVector.z);
    float roughnessVariation = keypath_value_noise(materialPixels * (isDeck ? 0.032 : 0.058)) - 0.5;
    float roughness = clamp(
        (isDeck ? 0.31 : 0.47) + roughnessVariation * (isDeck ? 0.055 : 0.035),
        0.12,
        0.82
    );
    float3 baseReflectance = isDeck
        ? float3(0.30, 0.27, 0.25)
        : float3(0.032, 0.034, 0.038);
    float3 microfacetFresnel = keypath_fresnel_schlick(viewDotHalf, baseReflectance);
    float microfacetDistribution = keypath_ggx_distribution(normalDotHalf, roughness);
    float microfacetVisibility = keypath_smith_visibility(
        normalDotView,
        normalDotLight,
        roughness
    );
    float3 microfacetSpecular = microfacetFresnel
        * microfacetDistribution
        * microfacetVisibility
        / max(0.04, 4.0 * normalDotView * normalDotLight);
    float specularPower = isDeck ? 88.0 : (isKey ? 42.0 : 34.0);
    float specular = pow(saturate(dot(normal, halfVector)), specularPower);
    float bevelSpecular = pow(
        saturate(dot(normal, halfVector)),
        isDeck ? 112.0 : 64.0
    ) * bevel;
    float fresnel = pow(1.0 - saturate(normal.z), 3.0);

    float3 darkMaterial = isDeck
        ? float3(0.010, 0.012, 0.016)
        : float3(0.0018, 0.0023, 0.0032);
    float3 litMaterial = input.fillColor.rgb;
    float3 surfaceColor = mix(darkMaterial, litMaterial, illumination);
    float verticalPosition = saturate(
        input.localPixels.y / max(1.0, input.halfSizePixels.y) * 0.5 + 0.5
    );
    surfaceColor *= mix(1.025, 0.94, verticalPosition * (isDeck ? 0.28 : 1.0));
    // A press tilts the cap away from the area light: the face darkens toward
    // its lower edge while the top bevel catches more, so compression stays
    // legible even under a saturated accent fill.
    surfaceColor *= mix(1.0, mix(1.05, 0.80, verticalPosition), pressure);
    float crownHighlight = isKey
        ? pow(saturate(1.0 - length(faceCoordinate) * 0.52), 2.2) * faceMask
        : 0.0;
    float lowerBevelCatch = isKey
        ? bevel * smoothstep(0.05, 0.82, distanceGradient.y)
        : 0.0;
    // A physical press remains legible at both cinematic endpoints. In the
    // dark room it appears as light leaking through the cap material; once the
    // area light arrives, the settled accent-filled face carries the state.
    surfaceColor = mix(
        surfaceColor,
        input.glowColor.rgb,
        keyPress * mix(0.12, 0.055, illumination)
    );

    // Stable, sub-pixel material variation prevents the aluminum deck and
    // graphite caps from reading as flat vector fills. The deck receives an
    // anisotropic brushed component while the caps retain much finer grain.
    float materialNoise = keypath_hash(floor(input.stageUV * uniforms.viewportSize * 0.72)) - 0.5;
    float brushedNoise = keypath_hash(float2(
        floor(input.stageUV.y * uniforms.viewportSize.y * 1.65),
        floor(input.stageUV.x * 37.0)
    )) - 0.5;
    surfaceColor += (
        materialNoise * (isDeck ? 0.015 : 0.0050)
        + brushedNoise * (isDeck ? 0.009 : 0.0)
    ) * mix(0.38, 1.0, illumination);

    float3 neutralLight = mix(float3(0.62, 0.72, 0.86), float3(1.0), illumination);
    surfaceColor *= mix(0.58, 1.04, illumination) + diffuse * illumination * 0.12;
    surfaceColor += microfacetSpecular
        * neutralLight
        * normalDotLight
        * mix(isDeck ? 0.032 : 0.018, isDeck ? 0.22 : 0.11, illumination);
    surfaceColor += neutralLight
        * crownHighlight
        * mix(0.0045, 0.018, illumination);
    surfaceColor += neutralLight
        * lowerBevelCatch
        * rimDirectionality
        * mix(0.018, 0.050, illumination);
    float pressTopCatch = isKey
        ? bevel * smoothstep(0.10, 0.85, -distanceGradient.y) * pressure
        : 0.0;
    surfaceColor += neutralLight * pressTopCatch * mix(0.10, 0.16, illumination);
    float broadSpecularStrength = isDeck ? 0.026 : (isKey ? 0.012 : 0.026);
    surfaceColor += neutralLight * (
        specular * (broadSpecularStrength + illumination * 0.13)
        + bevelSpecular * rimDirectionality * (0.035 + illumination * 0.16)
    );
    surfaceColor += float3(1.0, 0.82, 0.64) * grazingBand
        * (specular * 0.32 + fresnel * 0.08 + bevel * 0.04);

    // Before the moving source arrives, a low warm area light grazes the
    // keyboard from the right. It is strongest on the deck, catches key
    // bevels lightly, and vanishes exactly at the settled light endpoint.
    float entranceDarkness = 1.0 - pixelExposure;
    // The graze reaches further left and pools unevenly across the deck so
    // the metal reads as a broad photographic sweep instead of a uniform
    // tint; the noise scale is large enough to read as light, not texture.
    float rightGraze = smoothstep(uniforms.tuningB.x, 1.04, lightCoordinate)
        * entranceDarkness
        * (1.0 - pixelExposure * 0.75);
    float grazePool = 0.55 + 0.90 * keypath_value_noise(materialPixels * 0.004);
    float3 warmLightDirection = normalize(float3(0.86, -0.18, 0.48));
    float warmDiffuse = saturate(dot(normal, warmLightDirection));
    float3 warmHalfVector = normalize(warmLightDirection + float3(0.0, 0.0, 1.0));
    float warmSpecular = pow(
        saturate(dot(normal, warmHalfVector)),
        isDeck ? 78.0 : 52.0
    );
    float warmMaterialResponse = isDeck
        ? uniforms.tuningA.x + warmDiffuse * uniforms.tuningA.y
        : (isKey ? uniforms.tuningA.z + warmDiffuse * uniforms.tuningA.w : 0.0);
    float warmBevelResponse = isDeck
        ? bevel * 0.042 + warmSpecular * bevel * 0.070
        : (isKey
            ? (bevel * 0.058 + warmSpecular * bevel * 0.118)
                * (0.35 + directionalRim * 0.90)
            : 0.0);
    surfaceColor += float3(0.62, 0.43, 0.31)
        * rightGraze
        * grazePool
        * (warmMaterialResponse + warmBevelResponse);

    float edge = smoothstep(-2.2, -0.15, distance) * surfaceAlpha;
    float edgeIllumination = mix(0.10, 0.72, illumination) + grazingBand * 0.56;
    // In the dark room the lesson key's rim reads as a white bevel catching
    // the light, with the role hue carried by the surrounding halo; the
    // settled state returns to the pure accent stroke.
    float3 accentEdgeColor = mix(
        input.accentColor.rgb,
        float3(0.88, 0.94, 1.0),
        (1.0 - illumination) * 0.60
    );
    surfaceColor = mix(
        surfaceColor,
        accentEdgeColor,
        edge * borderStrength * 0.48 * edgeIllumination * emphasisRimShape
    );
    surfaceColor += input.glowColor.rgb
        * edge
        * glow
        * 0.32
        * (1.0 - pixelExposure * 0.55);
    surfaceColor += input.glowColor.rgb
        * edge
        * keyPress
        * mix(0.54, 0.24, illumination);
    float illuminatedBevel = isKey
        ? bevel * max(
            smoothstep(0.08, 0.78, distanceGradient.y),
            smoothstep(0.12, 0.82, -distanceGradient.x) * 0.72
        )
        : 0.0;
    float3 illuminatedBevelColor = mix(
        input.glowColor.rgb,
        float3(0.82, 0.90, 1.0),
        0.72
    );
    surfaceColor += illuminatedBevelColor
        * illuminatedBevel
        * instructionalEmphasis
        * emphasisRimShape
        * mix(0.24, 0.065, illumination);

    // A soft highlight along a chip's upper edge reads as light skimming a
    // raised glass surface, separating it from the keycaps beneath.
    float chipSheen = isChip
        ? bevel * smoothstep(0.15, 0.90, -distanceGradient.y)
        : 0.0;
    surfaceColor += neutralLight * chipSheen * (0.05 + illumination * 0.07);

    // A narrow internal rim makes the translucent legend light feel seated in
    // a real cap even though semantic glyphs remain native and accessible.
    float innerRim = exp(-abs(distance + 1.2) * 1.35) * surfaceAlpha;
    float3 innerRimColor = mix(float3(0.22, 0.23, 0.25), input.glowColor.rgb, glow);
    surfaceColor += innerRimColor
        * innerRim
        * mix(directionalRim + 0.25, 1.0, illumination)
        * (backlightStrength * 0.075 + keyPress * mix(0.52, 0.20, illumination));

    float nonGlowAlpha = 1.0
        - (1.0 - shadowAlpha)
            * (1.0 - wellAlpha)
            * (1.0 - skirtAlpha);
    float underAlpha = 1.0 - (1.0 - nonGlowAlpha) * (1.0 - glowAlpha);
    float3 shadowColor = mix(
        float3(0.0015, 0.0020, 0.0030),
        float3(0.035, 0.031, 0.028),
        illumination
    );
    float3 skirtColor = mix(
        float3(0.006, 0.008, 0.012),
        input.fillColor.rgb * 0.18,
        illumination
    );
    float3 entranceGlowColor = mix(
        float3(0.18, 0.20, 0.24),
        float3(0.82, 0.89, 1.0),
        illumination
    );
    float glowWeight = roleGlowAlpha + entranceGlowAlpha;
    float3 resolvedGlowColor = (
        input.glowColor.rgb * roleGlowAlpha
        + entranceGlowColor * entranceGlowAlpha
    ) / max(0.001, glowWeight);
    float3 nonGlowColor = mix(
        shadowColor,
        skirtColor,
        skirtAlpha / max(0.001, nonGlowAlpha)
    );
    float3 underColor = mix(
        nonGlowColor,
        resolvedGlowColor,
        glowAlpha / max(0.001, nonGlowAlpha + glowAlpha)
    );
    float finalAlpha = surfaceAlpha + underAlpha * (1.0 - surfaceAlpha);
    float3 finalColor = (
        surfaceColor * surfaceAlpha
        + underColor * underAlpha * (1.0 - surfaceAlpha)
    ) / max(0.001, finalAlpha);

    return float4(finalColor, finalAlpha * opacity);
}

fragment float4 keypath_keyboard_legend_fragment(
    KeyboardStageLegendVertexOut input [[stage_in]],
    constant KeyboardStageUniforms &uniforms [[buffer(1)]],
    texture2d<float, access::sample> legendAtlas [[texture(0)]]
) {
    constexpr sampler atlasSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );

    float coverage = saturate(legendAtlas.sample(atlasSampler, input.atlasUV).r);
    float opacity = saturate(input.parameters.x);
    float alpha = coverage * opacity * saturate(input.settledColor.a);
    if (alpha <= 0.0) {
        return float4(0.0);
    }

    bool reduceMotion = uniforms.entrance.y > 0.5;
    float pixelExposure = keypath_cinematic_exposure(
        uniforms.entrance.x,
        input.stageUV,
        reduceMotion,
        uniforms.cinematicLighting
    );
    float entranceDarkness = 1.0 - pixelExposure;

    // These are the linear-sRGB equivalents of the neutral 0.82/0.84/0.88
    // legend used during the dark hold. Keeping the aperture itself in the HDR
    // pass lets the bloom derive from real excess radiance instead of a second
    // screen-space text shadow.
    constexpr float3 darkLegendColor = float3(0.7484, 0.7484, 0.7100);
    // Apertures answer the same warm area light as the caps: legends near the
    // graze sit brighter and slightly warmer, far keys dimmer, so the
    // backlight reads as one panel lit from the side, not a uniform sheet.
    float lightAxis = saturate((input.stageUV.x - 0.30) / 0.70);
    float3 spatialDarkLegend = darkLegendColor
        * mix(uniforms.tuningD.z, uniforms.tuningD.w, lightAxis)
        * mix(float3(1.0), float3(1.03, 0.99, 0.92), lightAxis);
    float3 legendColor = mix(
        spatialDarkLegend,
        max(input.settledColor.rgb, float3(0.0)),
        pixelExposure
    );
    float entranceEmission = saturate(input.parameters.y);
    float roleEmission = saturate(input.parameters.z);
    float allowsBloom = saturate(input.parameters.w);
    float emission = entranceDarkness
        * mix(uniforms.tuningD.x, uniforms.tuningD.y, lightAxis)
        * (1.08 + entranceEmission * 0.78 + roleEmission * 0.42)
        * allowsBloom;
    float3 radiance = legendColor * (1.0 + emission);

    return float4(radiance, alpha);
}

static float3 keypath_bright_excess(float4 source) {
    if (source.a <= 0.00001) {
        return float3(0.0);
    }

    float3 radiance = max(source.rgb / source.a, float3(0.0));
    float3 excess = max(radiance - float3(1.0), float3(0.0)) * source.a;
    float peak = max(excess.r, max(excess.g, excess.b));
    return excess / (1.0 + peak * 0.35);
}

fragment float4 keypath_keyboard_bright_pass_fragment(
    KeyboardStageFullscreenOut input [[stage_in]],
    constant KeyboardStagePostUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> sourceTexture [[texture(0)]]
) {
    constexpr sampler sourceSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );

    float2 sourceSize = max(uniforms.sourceAndBloomSize.xy, float2(1.0));
    float2 bloomSize = max(uniforms.sourceAndBloomSize.zw, float2(1.0));
    float2 sourceTexel = 1.0 / sourceSize;
    float2 footprint = max(sourceSize / bloomSize, float2(1.0))
        * sourceTexel * 0.25;
    float3 bright = float3(0.0);
    bright += keypath_bright_excess(sourceTexture.sample(
        sourceSampler,
        input.uv + float2(-footprint.x, -footprint.y)
    ));
    bright += keypath_bright_excess(sourceTexture.sample(
        sourceSampler,
        input.uv + float2( footprint.x, -footprint.y)
    ));
    bright += keypath_bright_excess(sourceTexture.sample(
        sourceSampler,
        input.uv + float2(-footprint.x,  footprint.y)
    ));
    bright += keypath_bright_excess(sourceTexture.sample(
        sourceSampler,
        input.uv + float2( footprint.x,  footprint.y)
    ));
    return float4(bright * 0.25, 0.0);
}

static float3 keypath_gaussian_blur(
    texture2d<float, access::sample> sourceTexture,
    float2 uv,
    float2 axis,
    float2 textureSize
) {
    constexpr sampler blurSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );
    float2 texel = axis / max(textureSize, float2(1.0));
    float3 color = sourceTexture.sample(blurSampler, uv).rgb * 0.227027;
    color += sourceTexture.sample(blurSampler, uv + texel * 1.384615).rgb * 0.316216;
    color += sourceTexture.sample(blurSampler, uv - texel * 1.384615).rgb * 0.316216;
    color += sourceTexture.sample(blurSampler, uv + texel * 3.230769).rgb * 0.070270;
    color += sourceTexture.sample(blurSampler, uv - texel * 3.230769).rgb * 0.070270;
    return color;
}

fragment float4 keypath_keyboard_blur_horizontal_fragment(
    KeyboardStageFullscreenOut input [[stage_in]],
    constant KeyboardStagePostUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> sourceTexture [[texture(0)]]
) {
    float3 color = keypath_gaussian_blur(
        sourceTexture,
        input.uv,
        float2(1.0, 0.0),
        uniforms.sourceAndBloomSize.zw
    );
    return float4(color, 0.0);
}

fragment float4 keypath_keyboard_blur_vertical_fragment(
    KeyboardStageFullscreenOut input [[stage_in]],
    constant KeyboardStagePostUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> sourceTexture [[texture(0)]]
) {
    float3 color = keypath_gaussian_blur(
        sourceTexture,
        input.uv,
        float2(0.0, 1.0),
        uniforms.sourceAndBloomSize.zw
    );
    return float4(color, 0.0);
}

static float3 keypath_highlight_shoulder(float3 radiance) {
    constexpr float knee = 0.72;
    constexpr float range = 1.0 - knee;
    float3 positive = max(radiance, float3(0.0));
    float3 shoulder = knee + range
        * (1.0 - exp(-max(positive - knee, float3(0.0)) / range));
    return mix(positive, shoulder, step(float3(knee), positive));
}

fragment float4 keypath_keyboard_composite_fragment(
    KeyboardStageFullscreenOut input [[stage_in]],
    constant KeyboardStagePostUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::sample> sourceTexture [[texture(0)]],
    texture2d<float, access::sample> bloomTexture [[texture(1)]]
) {
    constexpr sampler compositeSampler(
        coord::normalized,
        address::clamp_to_edge,
        filter::linear
    );

    float4 source = sourceTexture.sample(compositeSampler, input.uv);
    float progress = saturate(uniforms.entranceAndDirection.x);
    bool reduceMotion = uniforms.entranceAndDirection.y > 0.5;
    float easedProgress = keypath_critically_damped_progress(progress);
    float2 direction = uniforms.entranceAndDirection.zw;
    float directionLength = length(direction);
    direction = directionLength > 0.0001
        ? direction / directionLength
        : float2(1.0, 0.0);

    float3 bloom = float3(0.0);
    float3 tightBloom = float3(0.0);
    bool hasBloom = uniforms.sourceAndBloomSize.z > 0.0
        && uniforms.sourceAndBloomSize.w > 0.0;
    if (hasBloom) {
        float2 bloomTexel = 1.0 / max(
            uniforms.sourceAndBloomSize.zw,
            float2(1.0)
        );
        float directionalOffset = reduceMotion ? 0.0 : (1.0 - easedProgress) * 0.65;
        bloom = bloomTexture.sample(
            compositeSampler,
            input.uv - direction * bloomTexel * directionalOffset
        ).rgb;

        float2 sourceTexel = 1.0 / max(
            uniforms.sourceAndBloomSize.xy,
            float2(1.0)
        );
        float2 tightOffset = sourceTexel * 1.25;
        tightBloom += keypath_bright_excess(sourceTexture.sample(
            compositeSampler,
            input.uv + float2(tightOffset.x, 0.0)
        ));
        tightBloom += keypath_bright_excess(sourceTexture.sample(
            compositeSampler,
            input.uv - float2(tightOffset.x, 0.0)
        ));
        tightBloom += keypath_bright_excess(sourceTexture.sample(
            compositeSampler,
            input.uv + float2(0.0, tightOffset.y)
        ));
        tightBloom += keypath_bright_excess(sourceTexture.sample(
            compositeSampler,
            input.uv - float2(0.0, tightOffset.y)
        ));
        tightBloom *= 0.25;
    }

    // Bloom is deliberately an entrance material effect. It vanishes at the
    // settled endpoint, and the >1 bright-pass threshold keeps ordinary white
    // key surfaces and native light UI from producing a gray haze.
    float bloomEnvelope = 1.0 - smoothstep(0.82, 1.0, progress);
    if (reduceMotion) {
        bloomEnvelope *= 0.72;
    }
    float3 bloomContribution = (
        tightBloom * 0.30
        + bloom * 0.12
    ) * bloomEnvelope;
    float bloomPeak = max(
        bloomContribution.r,
        max(bloomContribution.g, bloomContribution.b)
    );
    float bloomAlpha = saturate(bloomPeak * 0.45);
    float finalAlpha = source.a + bloomAlpha * (1.0 - source.a);
    if (finalAlpha <= 0.00001) {
        return float4(0.0);
    }

    float3 premultipliedRadiance = source.rgb + bloomContribution;
    float3 straightRadiance = premultipliedRadiance / finalAlpha;
    float3 mappedColor = keypath_highlight_shoulder(straightRadiance);

    // Static sub-LSB noise prevents banding in the dark-to-light shoulder. It
    // fades out before progress reaches one so the final light frame is clean.
    float2 sourceSize = max(uniforms.sourceAndBloomSize.xy, float2(1.0));
    float ditherEnvelope = 1.0 - smoothstep(0.92, 1.0, progress);
    float dither = (keypath_hash(floor(input.uv * sourceSize)) - 0.5)
        * (1.0 / 2048.0)
        * ditherEnvelope;
    mappedColor = saturate(mappedColor + dither);

    return float4(mappedColor * finalAlpha, finalAlpha);
}
