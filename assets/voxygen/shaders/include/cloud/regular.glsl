#include <random.glsl>
#include <lod.glsl>

float falloff(float x) {
    return pow(max(x > 0.577 ? (0.3849 / x - 0.1) : (0.9 - x * x), 0.0), 4);
}

float emission_strength = clamp((sin(time_of_day.x / (3600 * 24)) - 0.8) / 0.1, 0, 1);

// Return the 'broad' density of the cloud at a position. This gets refined later with extra noise, but is important
// for computing light access.
float cloud_broad(vec3 pos) {
    return 0.0
        + 2 * (noise_3d(pos / vec3(vec2(30000.0), 20000.0) / cloud_scale + 1000.0) - 0.5)
    ;
}

// Returns vec4(r, g, b, density)
vec4 cloud_at(vec3 pos, float dist, out vec3 emission) {
    // Natural attenuation of air (air naturally attenuates light that passes through it)
    // Simulate the atmosphere thinning as you get higher. Not physically accurate, but then
    // it can't be since Veloren's world is flat, not spherical.
    float atmosphere_alt = CLOUD_AVG_ALT + 40000.0;
    // Veloren's world is flat. This is, to put it mildly, somewhat non-physical. With the earth as an infinitely-big
    // plane, the atmosphere is therefore capable of scattering 100% of any light source at the horizon, no matter how
    // bright, because it has to travel through an infinite amount of atmosphere. This doesn't happen in reality
    // because the earth has curvature and so there is an upper bound on the amount of atmosphere that a sunset must
    // travel through. We 'simulate' this by fading out the atmosphere density with distance.
    float flat_earth_hack = 1.0 / (1.0 + dist * 0.0001);
    float air = 0.025 * clamp((atmosphere_alt - pos.z) / 20000, 0, 1) * flat_earth_hack;

    float alt = alt_at(pos.xy - focus_off.xy);

    // Mist sits close to the ground in valleys (TODO: use base_alt to put it closer to water)
    float mist_min_alt = 0.5;
    #if (CLOUD_MODE >= CLOUD_MODE_MEDIUM)
        mist_min_alt = (textureLod(sampler2D(t_noise, s_noise), pos.xy / 50000.0, 0).x - 0.5) * 1.5 + 0.5;
    #endif
    mist_min_alt = view_distance.z * 1.5 * (1.0 + mist_min_alt * 0.5) + alt * 0.5 + 250;
    const float MIST_FADE_HEIGHT = 1000;
    float mist = 0.01 * pow(clamp(1.0 - (pos.z - mist_min_alt) / MIST_FADE_HEIGHT, 0.0, 1), 10.0) * flat_earth_hack;

    vec3 wind_pos = vec3(pos.xy + wind_offset, pos.z + noise_2d(pos.xy / 20000) * 500);

    // Clouds
    float cloud_tendency = cloud_tendency_at(pos.xy);
    float cloud = 0;

    if (mist > 0.0) {
        mist *= 0.5
        #if (CLOUD_MODE >= CLOUD_MODE_LOW)
            + 1.0 * (noise_2d(wind_pos.xy / 5000) - 0.5)
        #endif
        #if (CLOUD_MODE >= CLOUD_MODE_MEDIUM)
            + 0.25 * (noise_3d(wind_pos / 1000) - 0.5)
        #endif
        ;
    }

    //vec2 cloud_attr = get_cloud_heights(wind_pos.xy);
    float sun_access = 0.0;
    float moon_access = 0.0;
    float cloud_sun_access = 0.0;
    float cloud_moon_access = 0.0;
    float cloud_broad_a = 0.0;
    float cloud_broad_b = 0.0;
    // This is a silly optimisation but it actually nets us a fair few fps by skipping quite a few expensive calcs
    if ((pos.z < CLOUD_AVG_ALT + 15000.0 && cloud_tendency > 0.0)) {
        // Turbulence (small variations in clouds/mist)
        const float turb_speed = -1.0; // Turbulence goes the opposite way
        vec3 turb_offset = vec3(1, 1, 0) * time_of_day.x * turb_speed;

        float CLOUD_DEPTH = (view_distance.w - view_distance.z) * 0.8;
        const float CLOUD_DENSITY = 10000.0;
        const float CLOUD_ALT_VARI_WIDTH = 100000.0;
        const float CLOUD_ALT_VARI_SCALE = 5000.0;
        float cloud_alt = CLOUD_AVG_ALT + alt * 0.5;

        cloud_broad_a = cloud_broad(wind_pos + sun_dir.xyz * 250);
        cloud_broad_b = cloud_broad(wind_pos - sun_dir.xyz * 250);
        cloud = cloud_tendency + (0.0
            + 24 * (cloud_broad_a + cloud_broad_b) * 0.5
        #if (CLOUD_MODE >= CLOUD_MODE_MINIMAL)
            + 4 * (noise_3d((wind_pos + turb_offset) / 2000.0 / cloud_scale) - 0.5)
        #endif
        #if (CLOUD_MODE >= CLOUD_MODE_LOW)
            + 0.75 * (noise_3d((wind_pos + turb_offset * 0.5) / 750.0 / cloud_scale) - 0.5)
        #endif
        #if (CLOUD_MODE >= CLOUD_MODE_HIGH)
            + 0.75 * (noise_3d(wind_pos / 500.0 / cloud_scale) - 0.5)
        #endif
        ) * 0.01;
        cloud = pow(max(cloud, 0), 3) * sign(cloud);
        cloud *= CLOUD_DENSITY * sqrt(cloud_tendency) * falloff(abs(pos.z - cloud_alt) / CLOUD_DEPTH);

        // What proportion of sunlight is *not* being blocked by nearby cloud? (approximation)
        // Basically, just throw together a few values that roughly approximate this term and come up with an average
        cloud_sun_access = exp((
            // Cloud density gradient
            0.25 * (cloud_broad_a - cloud_broad_b + (0.25 * (noise_3d(wind_pos / 4000 / cloud_scale) - 0.5) + 0.1 * (noise_3d(wind_pos / 1000 / cloud_scale) - 0.5)))
        #if (CLOUD_MODE >= CLOUD_MODE_HIGH)
            // More noise
            + 0.01 * (noise_3d(wind_pos / 500) / cloud_scale - 0.5)
        #endif
        ) * 15.0 - 1.5) * 1.5;
        // Since we're assuming the sun/moon is always above (not always correct) it's the same for the moon
        cloud_moon_access = 1.0 - cloud_sun_access;
    }

    // Keeping this because it's something I'm likely to reenable later
    /*
    #if (CLOUD_MODE >= CLOUD_MODE_HIGH)
        // Try to calculate a reasonable approximation of the cloud normal
        float cloud_tendency_x = cloud_tendency_at(pos.xy + vec2(100, 0));
        float cloud_tendency_y = cloud_tendency_at(pos.xy + vec2(0, 100));
        vec3 cloud_norm = vec3(
            (cloud_tendency - cloud_tendency_x) * 4,
            (cloud_tendency - cloud_tendency_y) * 4,
            (pos.z - cloud_attr.x) / cloud_attr.y + 0.5
        );
        cloud_sun_access = mix(max(dot(-sun_dir.xyz, cloud_norm) - 1.0, 0.025), cloud_sun_access, 0.25);
        cloud_moon_access = mix(max(dot(-moon_dir.xyz, cloud_norm) - 0.6, 0.025), cloud_moon_access, 0.25);
    #endif
    */

    float mist_sun_access = exp(mist);
    float mist_moon_access = mist_sun_access;
    sun_access = mix(cloud_sun_access, mist_sun_access, clamp(mist * 20000, 0, 1));
    moon_access = mix(cloud_moon_access, mist_moon_access, clamp(mist * 20000, 0, 1));

    // Prevent mist (i.e: vapour beneath clouds) being accessible to the sun to avoid visual problems
    //float suppress_mist = clamp((pos.z - cloud_attr.x + cloud_attr.y) / 300, 0, 1);
    //sun_access *= suppress_mist;
    //moon_access *= suppress_mist;

    // Prevent clouds and mist appearing underground (but fade them out gently)
    float not_underground = clamp(1.0 - (alt - (pos.z - focus_off.z)) / 80.0 + dist * 0.001, 0, 1);
    sun_access *= not_underground;
    moon_access *= not_underground;
    float vapor_density = (mist + cloud) * not_underground;

    if (emission_strength <= 0.0) {
        emission = vec3(0);
    } else {
        float emission_alt = CLOUD_AVG_ALT * 2.0 + (noise_3d(vec3(wind_pos.xy * 0.0001 + cloud_tendency * 0.2, time_of_day.x * 0.0002)) - 0.5) * 6000;
        #if (CLOUD_MODE >= CLOUD_MODE_MEDIUM)
            emission_alt += (noise_3d(vec3(wind_pos.xy * 0.0005 + cloud_tendency * 0.2, emission_alt * 0.0001 + time_of_day.x * 0.001)) - 0.5) * 1000;
        #endif
        float tail = (textureLod(sampler2D(t_noise, s_noise), wind_pos.xy * 0.00005, 0).x - 0.5) * 4 + (pos.z - emission_alt) * 0.0001;
        vec3 emission_col = vec3(0.8 + tail * 1.5, 0.5 - tail * 0.2, 0.3 + tail * 0.2);
        float emission_nz = max(pow(textureLod(sampler2D(t_noise, s_noise), wind_pos.xy * 0.000015, 0).x, 8), 0.01) * 0.25 / (10.0 + abs(pos.z - emission_alt) / 80);
        emission = emission_col * emission_nz * emission_strength * max(sun_dir.z, 0) * 500000 / (1000.0 + abs(pos.z - emission_alt) * 0.1);
    }

    // We track vapor density and air density separately. Why? Because photons will ionize particles in air
    // leading to rayleigh scattering, but water vapor will not. Tracking these indepedently allows us to
    // get more correct colours.
    return vec4(sun_access, moon_access, vapor_density, air);
}

float atan2(in float y, in float x) {
    bool s = (abs(x) > abs(y));
    return mix(PI/2.0 - atan(x,y), atan(y,x), s);
}

const float DIST_CAP = 50000;
#if (CLOUD_MODE == CLOUD_MODE_ULTRA)
    const uint QUALITY = 200u;
#elif (CLOUD_MODE == CLOUD_MODE_HIGH)
    const uint QUALITY = 40u;
#elif (CLOUD_MODE == CLOUD_MODE_MEDIUM)
    const uint QUALITY = 18u;
#elif (CLOUD_MODE == CLOUD_MODE_LOW)
    const uint QUALITY = 6u;
#elif (CLOUD_MODE == CLOUD_MODE_MINIMAL)
    const uint QUALITY = 2u;
#endif

const float STEP_SCALE = DIST_CAP / (10.0 * float(QUALITY));

float step_to_dist(float step, float quality) {
    return pow(step, 2) * STEP_SCALE / quality;
}

float dist_to_step(float dist, float quality) {
    return pow(dist / STEP_SCALE * quality, 0.5);
}

vec3 get_cloud_color(vec3 surf_color, vec3 dir, vec3 origin, const float time_of_day, float max_dist, const float quality) {
    // Limit the marching distance to reduce maximum jumps
    max_dist = min(max_dist, DIST_CAP);

    origin.xyz += focus_off.xyz;

    // This hack adds a little direction-dependent noise to clouds. It's not correct, but it very cheaply
    // improves visual quality for low cloud settings
    float splay = 1.0;
    #if (CLOUD_MODE == CLOUD_MODE_MINIMAL)
        splay += (textureLod(sampler2D(t_noise, s_noise), vec2(atan2(dir.x, dir.y) * 2 / PI, dir.z) * 5.0 - time_of_day * 0.00005, 0).x - 0.5) * 0.025 / (1.0 + pow(dir.z, 2) * 10);
    #endif

    /* const float RAYLEIGH = 0.25; */
    const vec3 RAYLEIGH = vec3(0.025, 0.1, 0.5);

    // Proportion of sunlight that get scattered back into the camera by clouds
    float sun_scatter = dot(-dir, sun_dir.xyz) * 0.5 + 0.7;
    float moon_scatter = dot(-dir, moon_dir.xyz) * 0.5 + 0.7;
    float net_light = get_sun_brightness() + get_moon_brightness();
    vec3 sky_color = RAYLEIGH * net_light;
    vec3 sky_light = get_sky_light(dir, time_of_day, false);

    float cdist = max_dist;
    float ldist = cdist;
    // i is an emergency brake
    float min_dist = clamp(max_dist / 4, 0.25, 24);
    for (int i = 0; cdist > min_dist && i < 250; i ++) {
        ldist = cdist;
        cdist = step_to_dist(trunc(dist_to_step(cdist - 0.25, quality)), quality);

        vec3 emission;
        // `sample` is a reserved keyword
        vec4 sample_ = cloud_at(origin + dir * ldist * splay, ldist, emission);

        vec2 density_integrals = max(sample_.zw, vec2(0));

        float sun_access = max(sample_.x, 0);
        float moon_access = max(sample_.y, 0);
        float cloud_scatter_factor = density_integrals.x;
        float global_scatter_factor = density_integrals.y;

        float cloud_darken = pow(1.0 / (1.0 + cloud_scatter_factor), (ldist - cdist) * 0.01);
        float global_darken = pow(1.0 / (1.0 + global_scatter_factor), (ldist - cdist) * 0.01);

        surf_color =
            // Attenuate light passing through the clouds
            surf_color * cloud_darken * global_darken +
            // Add the directed light light scattered into the camera by the clouds and the atmosphere (global illumination)
            get_sun_color() * sun_scatter * get_sun_brightness() * (sun_access * (1.0 - cloud_darken) /*+ sky_color * global_scatter_factor*/) +
            get_moon_color() * moon_scatter * get_moon_brightness() * (moon_access * (1.0 - cloud_darken) /*+ sky_color * global_scatter_factor*/) +
            sky_light * (1.0 - global_darken) +
            emission * density_integrals.y;
    }

    return surf_color;
}
