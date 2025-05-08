#version 430 core
#include "common.glsl"
#include "sdf.glsl"
#include "mapping.glsl"
#include "lighting.glsl"

in vec3 color;
layout (location = 0) out vec4 FragColor;

float rMarch(vec3 rOrig, vec3 rDir) {
    float dOrig = 0.0; // distance from ray origin

    for(int i=0; i<MAX_STEPS; i++) {
        vec3 rPos = rOrig + rDir * dOrig;
        float dSurf = calcSDF(rPos, true).x;
        dOrig += dSurf;
        if(dOrig > MAX_DIST_TO_TRAVEL || abs(dSurf) < MIN_DIST_TO_SDF*clamp(((dOrig*dOrig-3)*LOD_MULTIPLIER),1,MAX_DIST_TO_TRAVEL*MAX_DIST_TO_TRAVEL*LOD_MULTIPLIER)) break;
        //if(dOrig > MAX_DIST_TO_TRAVEL || abs(dSurf) < MIN_DIST_TO_SDF) break;
    }

    return dOrig;
}

vec2 getUV(vec2 offset) {
    return ((gl_FragCoord.xy + offset) - 0.5 * u_resolution.xy) / u_resolution.y;
}

vec3 rCam(vec2 offset) {
    vec2 uv = getUV(offset);
    vec3 rOrig = u_camPos;
    vec3 lookat = rOrig+u_camTarget;
    float zoom = max(0.5,(u_scroll*0.05)+0.5);
    vec3 forward = normalize(lookat-rOrig),
    right = normalize(cross(forward, vec3(0, 1., 0))),
    up = cross(right, forward),
    center = forward*zoom,
    intersection = center + uv.x*right + uv.y*up,
    dir = normalize(intersection);
    return dir;
}

vec3 applyFog(vec3 color, float distance, vec3 rayDir, vec3 sunDir) {
    float fogAmount = 1.0 - exp(-distance * 0.00008);
    float sunAmount = max(dot(rayDir, sunDir), 0.0);
    vec3 fogColor = mix(
        vec3(0.5, 0.6, 0.7), // base fog color
        vec3(1.0, 0.9, 0.7), // sun tint
        pow(sunAmount, 8.0)
    );
    return mix(color, fogColor, fogAmount);
}

vec3 applyWaterFog(vec3 color, float distance, vec3 rayDir, vec3 sunDir) {
    float fogAmount = 1.0 - exp(-distance * 0.0002);
    float sunAmount = max(dot(rayDir, sunDir), 0.0);
    vec3 fogColor = mix(
        vec3(0.1, 0.2, 0.3), // deep water color
        vec3(0.3, 0.5, 0.6), // shallow water color with sun
        pow(sunAmount, 4.0)
    );
    return mix(color, fogColor, fogAmount);
}

//float linstep(in float mn, in float mx, in float x){
//    return clamp((x - mn)/(mx - mn), 0., 1.);
//}
//
//const vec3 lgt = vec3(-.523, .41, -.747);
//const float FAR = 400.;
//vec3 scatter(vec3 ro, vec3 rd)
//{
//    float sd= max(dot(lgt, rd)*0.5+0.5,0.);
//    float dtp = 13.-(ro + rd*(FAR)).y*3.5;
//    float hori = (linstep(-1500., 0.0, dtp) - linstep(11., 500., dtp))*1.;
//    hori *= pow(sd,.04);
//
//    vec3 col = vec3(0);
//    col += pow(hori, 200.)*vec3(1.0, 0.7,  0.5)*3.;
//    col += pow(hori, 25.)* vec3(1.0, 0.5,  0.25)*.3;
//    col += pow(hori, 7.)* vec3(1.0, 0.4, 0.25)*.8;
//
//    return col;
//}
//
//vec3 nmzHash33(vec3 q)
//{
//    uvec3 p = uvec3(ivec3(q));
//    p = p*uvec3(374761393U, 1103515245U, 668265263U) + p.zxy + p.yzx;
//    p = p.yzx*(p.zxy^(p >> 3U));
//    return vec3(p^(p >> 16U))*(1.0/vec3(0xffffffffU));
//}
//
//vec3 stars(in vec3 p)
//{
//    vec3 c = vec3(0.);
//    float res = u_resolution.x*0.8;
//
//    for (float i=0.;i<3.;i++)
//    {
//        vec3 q = fract(p*(.15*res))-0.5;
//        vec3 id = floor(p*(.15*res));
//        vec2 rn = nmzHash33(id).xy;
//        float c2 = 1.-smoothstep(0.,.6,length(q));
//        c2 *= step(rn.x,.0005+i*i*0.001);
//        c += c2*(mix(vec3(1.0,0.49,0.1),vec3(0.75,0.9,1.),rn.y)*0.25+0.75);
//        p *= 1.4;
//    }
//    return c*c*.7;
//}
// Hash function for star distribution
//vec3 hash(vec3 q) {
//    uvec3 p = uvec3(ivec3(q));
//    p = p * uvec3(374761393U, 1103515245U, 668265263U) + p.zxy + p.yzx;
//    p = p.yzx * (p.zxy ^ (p >> 3U));
//    return vec3(p ^ (p >> 16U)) * (1.0 / vec3(0xffffffffU));
//}
//
//// Helper function for linear interpolation with clamping
//float linstep(float mn, float mx, float x) {
//    return clamp((x - mn)/(mx - mn), 0.0, 1.0);
//}
//
//// Returns vec2(planetId, radius) for the closest planet
//// If no planet is close enough, returns vec2(-1.0, 1.0)
//vec2 closestPlanetInfo(vec3 position) {
//    float minDist = 1000000.0;
//    int closestId = -1;
//    float closestRadius = 1.0;
//
//    // Loop through all objects to find planets
//    for (int i = 0; i < u_countObjects; i++) {
//        // Assumption: planets are spherical objects
//        // You might need a flag or some other way to identify planets
//        vec3 planetPos = vec3(visibleObjects[i].x, visibleObjects[i].y, visibleObjects[i].z);
//        float planetRadius = visibleObjects[i].i; // Assuming uniform scale for planets
//
//        float dist = distance(position, planetPos) - planetRadius;
//
//        if (dist < minDist) {
//            minDist = dist;
//            closestId = i;
//            closestRadius = planetRadius;
//        }
//    }
//
//    // Only consider planets that are close enough to affect the sky
//    float proximityThreshold = 100.0; // Adjust based on your scene scale
//    if (minDist < proximityThreshold) {
//        return vec2(float(closestId), closestRadius);
//    } else {
//        return vec2(-1.0, 1.0); // No planet close enough
//    }
//}
//
//vec3 renderStarrySky(vec3 ro, vec3 rd) {
//    // Get information about closest planet
//    vec2 planetInfo = closestPlanetInfo(ro);
//    vec3 planetCenter = planetInfo.x >= 0.0 ? vec3(visibleObjects[int(planetInfo.x)].x, visibleObjects[int(planetInfo.x)].y, visibleObjects[int(planetInfo.x)].z) : vec3(0.0);
//    float planetRadius = planetInfo.y;
//
//    // If no planet is close enough, use a default up vector
//    vec3 localUp;
//    if (planetInfo.x < 0.0) {
//        localUp = vec3(0.0, 1.0, 0.0);
//    } else {
//        // Calculate up vector based on player position relative to closest planet
//        localUp = normalize(ro - planetCenter);
//    }
//
//    // Light direction for the sky gradient
//    vec3 lightDir = normalize(u_lightPos);
//    float farDist = 400.0;
//
//    // Generate a local reference frame for the sky
//    vec3 localForward = normalize(u_camTarget);
//    vec3 localRight = normalize(cross(localForward, localUp));
//    localForward = normalize(cross(localUp, localRight)); // Re-orthogonalize
//
//    // Calculate local horizon and zenith angles
//    float horizonDot = dot(localUp, rd);
//    float timeOfDay = dot(lightDir, localUp); // -1 to 1: -1 when sun is below, 1 when above
//
//    // Local "forward" direction on horizon for determining sun position in sky
//    vec3 horizonForward = normalize(lightDir - localUp * dot(lightDir, localUp));
//    float sunAzimuth = dot(horizonForward, rd - localUp * horizonDot);
//
//    // Base sky colors for different times of day
//    vec3 dayColor = vec3(0.5, 0.7, 1.0);
//    vec3 nightColor = vec3(0.05, 0.05, 0.1);
//    vec3 sunsetColor = vec3(0.8, 0.4, 0.2);
//
//    // Sun/moon parameters
//    float sunSize = 0.01;
//    float moonSize = 0.005;
//    float sunIntensity = 5.0;
//    float moonIntensity = 0.7;
//
//    // Calculate sun and moon visibility based on local orientation
//    float sunDot = max(dot(lightDir, rd), 0.0);
//    float moonDot = max(dot(-lightDir, rd), 0.0);
//
//    // Sun and moon disks
//    float sun = smoothstep(1.0 - sunSize, 1.0, sunDot);
//    float moon = smoothstep(1.0 - moonSize, 1.0 - moonSize*0.2, moonDot);
//
//    // Horizon gradient based on local up direction
//    float horizonGradient = horizonDot * 0.5 + 0.5; // 0 at horizon, 1 at zenith
//
//    // Scale horizon sharpness based on planet size - larger planets have sharper horizons
//    float planetSizeMultiplier = clamp(planetRadius / 10.0, 0.3, 3.0);
//    horizonGradient = pow(horizonGradient, 1.0 / planetSizeMultiplier);
//
//    // Sky base color based on time of day
//    vec3 skyColor;
//    if (timeOfDay > 0.1) {
//        // Day
//        float t = smoothstep(0.1, 0.5, timeOfDay);
//        skyColor = mix(sunsetColor, dayColor, t);
//        skyColor = mix(skyColor, vec3(0.7, 0.8, 1.0), horizonGradient); // Blend with blue at zenith
//    } else if (timeOfDay > -0.1) {
//        // Sunset/sunrise
//        float horizonGlow = pow(1.0 - abs(horizonDot), 4.0 * planetSizeMultiplier) * pow(max(sunAzimuth, 0.0), 16.0);
//        skyColor = sunsetColor + vec3(1.0, 0.6, 0.2) * horizonGlow * 2.0;
//        skyColor *= mix(vec3(0.8, 0.9, 1.0), vec3(1.0, 0.6, 0.2), (1.0 - horizonGradient) * 0.7);
//    } else {
//        // Night
//        skyColor = nightColor;
//    }
//
//    // Add sun/moon with time of day modulation
//    skyColor += sunIntensity * sun * vec3(1.0, 0.9, 0.7) * smoothstep(-0.2, 0.2, timeOfDay);
//    skyColor += moonIntensity * moon * vec3(0.9, 0.9, 1.0) * smoothstep(0.2, -0.2, timeOfDay);
//
//    // Add subtle crater texture to moon
//    if (moon > 0.01) {
//        float craterPattern = hash(rd * 100.0).x;
//        craterPattern = smoothstep(0.3, 0.7, craterPattern);
//        craterPattern *= smoothstep(0.0, 0.4, moonDot - (1.0 - moonSize*1.2));
//        skyColor -= vec3(0.05, 0.05, 0.05) * craterPattern * moonIntensity * smoothstep(0.2, -0.2, timeOfDay);
//    }
//
//    // Stars (only visible at night)
//    float starVisibility = smoothstep(0.1, -0.1, timeOfDay);
//    vec3 starColor = vec3(0.0);
//    if (starVisibility > 0.01) {
//        float res = u_resolution.x * 0.8;
//        vec3 p = rd;
//
//        for (float i = 0.0; i < 3.0; i++) {
//            float scale = 0.15 * res;
//            vec3 q = fract(p * scale) - 0.5;
//            vec3 id = floor(p * scale);
//            vec2 rn = hash(id).xy;
//            float c2 = 1.0 - smoothstep(0.0, 0.6, length(q));
//            c2 *= step(rn.x, 0.0005 + i * i * 0.001);
//            starColor += c2 * (mix(vec3(1.0, 0.49, 0.1), vec3(0.75, 0.9, 1.0), rn.y) * 0.25 + 0.75);
//            p *= 1.4;
//        }
//        starColor = starColor * starColor * 0.7 * starVisibility;
//    }
//
//    // Combine sky and stars
//    return skyColor + starColor;
//}

void main() {
    vec2 fragCoord = gl_FragCoord.xy;
    vec2 uv = fragCoord/u_resolution.xy;
    vec2 p = uv * 2.0 - 1.0;
    p.x *= u_resolution.x / u_resolution.y;

    // Camera setup (OLD SYSTEM)
    vec3 cameraPos = u_camPos;
    vec3 rayDir = rCam(vec2(0.0));

    // Ray marching
    float dist = rMarch(cameraPos, rayDir);

    // Initialize color
    vec3 color;

    if (dist < MAX_DIST_TO_TRAVEL) {
        // Hit point
        vec3 hitPos = cameraPos + rayDir * dist;

        // Get object ID that was hit
        float objectID = calcSDF(hitPos, true).y;

        // Choose shading method based on render mode
        if (u_renderMode == 0) {
            // Phong shading
            color = getLightPhong(hitPos, rayDir, objectID);
        } else {
            // PBR shading
            color = getLightPBR(hitPos, rayDir, objectID);
        }

        // Apply fog
        vec3 sunDir = normalize(vec3(0.5, 0.8, 0.2));
        color = applyFog(color, dist, rayDir, sunDir);
    }
    else {
        // Sky gradient
        float t = 0.5 * (rayDir.y + 1.0);
        color = mix(vec3(1.0), vec3(0.15, 0.3, 1.0), t);

//        vec3 scatt = scatter(cameraPos, rayDir);
//        color = stars(rayDir)*(1.0-clamp(dot(scatt, vec3(1.3)),0.,1.));
//        color = renderStarrySky(cameraPos, rayDir);
    }

    // 3) add micro-dither to suppress any residual posterization
    float d = (fract(sin(dot(gl_FragCoord.xy,vec2(12.9898,78.233))) * 43758.5453) - 0.5) / 255.0;
    color += d;

    // Gamma correction
    color = pow(color, vec3(1.0/2.2));

    // Output final color
    FragColor = vec4(color, 1.0);
}

