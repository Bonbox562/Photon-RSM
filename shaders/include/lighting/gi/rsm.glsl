#if !defined INCLUDE_LIGHTING_GI_RSM
#define INCLUDE_LIGHTING_GI_RSM

#include "/include/lighting/shadows/distortion.glsl"
#include "/include/utility/encoding.glsl"

vec3 get_rsm_gi(vec3 scene_pos, vec3 normal, float skylight, float dither) {
    float skylight_fade = linear_step(1.0 / 15.0, 4.0 / 15.0, skylight);
    if(skylight_fade < eps) {
        return vec3(0.0);
    }

    vec3 shadow_view_pos = transform(shadowModelView, scene_pos);
    vec3 shadow_clip_pos = project_ortho(shadowProjection, shadow_view_pos);

    float edge_fade = 1.0 - linear_step(0.8, 1.0, max_of(abs(shadow_clip_pos.xy)));
    if(edge_fade < eps) {
        return vec3(0.0);
    }

    float radius_clip = RSM_GI_RADIUS * shadowProjection[0].x;

    ivec2 shadow_res = textureSize(shadowtex0, 0);
    float vpl_area_sq = sqr(RSM_GI_RADIUS) * rcp(float(RSM_GI_SAMPLES));

    vec3 gi = vec3(0.0);
    float rotation = dither * tau;

    for(int i = 0; i < RSM_GI_SAMPLES; ++i) {
        float u = (float(i) + dither) / float(RSM_GI_SAMPLES);
        float theta = float(i) * golden_angle + rotation;
        float weight = u;

        vec2 offset = (u * radius_clip) * vec2(cos(theta), sin(theta));
        vec2 sample_clip = shadow_clip_pos.xy + offset;

        vec2 sample_uv = sample_clip / get_distortion_factor(sample_clip);
        sample_uv = sample_uv * 0.5 + 0.5;
        if(clamp01(sample_uv) != sample_uv) {
            continue;
        }

        ivec2 texel = ivec2(sample_uv * vec2(shadow_res));

        vec4 rsm_data = texelFetch(shadowcolor1, texel, 0);
        vec2 albedo_b_valid = unpack_unorm_2x8(rsm_data.w);
        if(albedo_b_valid.y < 0.5) {
            continue;
        }

        vec3 vpl_normal = decode_unit_vector(rsm_data.xy);
        vec3 vpl_albedo = vec3(unpack_unorm_2x8(rsm_data.z), albedo_b_valid.x);

        float sample_depth = texelFetch(shadowtex0, texel, 0).x;
        vec3 vpl_clip = vec3(sample_clip, (sample_depth * 2.0 - 1.0) / SHADOW_DEPTH_SCALE);
        vec3 vpl_view = project_ortho(shadowProjectionInverse, vpl_clip);
        vec3 vpl_scene = transform(shadowModelViewInverse, vpl_view);

        vec3 dir = vpl_scene - scene_pos;
        float dist_sq = dot(dir, dir);
        vec3 dir_n = dir * inversesqrt(dist_sq + eps);

        float cos_receiver = max0(dot(normal, dir_n));
        float cos_vpl = max0(dot(vpl_normal, -dir_n));
        float vpl_lit = max0(dot(vpl_normal, light_dir));

        float falloff = rcp(dist_sq + vpl_area_sq);

        gi += vpl_albedo * (vpl_lit * cos_receiver * cos_vpl * falloff * weight);
    }

    gi *= 12.0 * sqr(RSM_GI_RADIUS) * rcp(float(RSM_GI_SAMPLES));

    return gi * (skylight_fade * edge_fade);
}

#endif // INCLUDE_LIGHTING_GI_RSM
