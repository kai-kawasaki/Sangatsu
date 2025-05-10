#version 430 core
#include "common.glsl"
#include "sdf.glsl"
#include "mapping.glsl"
#include "lighting.glsl"

in vec3 color;
layout (location = 0) out vec4 FragColor;

//float rMarch(vec3 rOrig, vec3 rDir) {
//    float dOrig = 0.0; // distance from ray origin
//
//    for(int i=0; i<MAX_STEPS; i++) {
//        vec3 rPos = rOrig + rDir * dOrig;
//        float dSurf = calcSDF(rPos).x;
//        dOrig += dSurf;
//
//        if(dOrig > MAX_DIST_TO_TRAVEL || abs(dSurf) < MIN_DIST_TO_SDF*clamp(((dOrig*dOrig-3)*LOD_MULTIPLIER),1,MAX_DIST_TO_TRAVEL*MAX_DIST_TO_TRAVEL*LOD_MULTIPLIER)) break;
//        //if(dOrig > MAX_DIST_TO_TRAVEL || abs(dSurf) < MIN_DIST_TO_SDF) break;
//    }
//
//    return dOrig;
//}

//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
// 1) Ray ⇔ AABB slab test, returns (tEnter, tExit)
//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
vec2 intersectRayAABB(vec3 ro, vec3 rd, vec3 bMin, vec3 bMax) {
    // Handle zero components in ray direction
    vec3 invR = vec3(
    abs(rd.x) < 1e-6 ? 1e6 * sign(rd.x) : 1.0 / rd.x,
    abs(rd.y) < 1e-6 ? 1e6 * sign(rd.y) : 1.0 / rd.y,
    abs(rd.z) < 1e-6 ? 1e6 * sign(rd.z) : 1.0 / rd.z
    );

    vec3 t0s = (bMin - ro) * invR;
    vec3 t1s = (bMax - ro) * invR;
    vec3 tMin = min(t0s, t1s);
    vec3 tMax = max(t0s, t1s);

    float tEnter = max(max(tMin.x, tMin.y), tMin.z);
    float tExit = min(min(tMax.x, tMax.y), tMax.z);

    // Handle special case when ray origin is inside box
    if (ro.x >= bMin.x && ro.x <= bMax.x &&
    ro.y >= bMin.y && ro.y <= bMax.y &&
    ro.z >= bMin.z && ro.z <= bMax.z) {
        tEnter = 0.0;
    }

    return vec2(tEnter, tExit);
}

//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
// 2) Sphere-trace *only* in [t0,t1].  Returns >0 on hit, else −1
//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
float sphereTraceSegment(vec3 ro, vec3 rd, float t0, float t1) {
    float t = max(t0, 0.0);
    for(int i = 0; i < MAX_STEPS; i++) {
        if (t > t1) break;
        vec3 pos = ro + rd * t;
        float d = calcSDF(pos).x;
//        if(t > MAX_DIST_TO_TRAVEL || abs(d) < MIN_DIST_TO_SDF*clamp(((t*t-3)*LOD_MULTIPLIER),1,MAX_DIST_TO_TRAVEL*MAX_DIST_TO_TRAVEL*LOD_MULTIPLIER)) return t;
        if (d < MIN_DIST_TO_SDF) return t;
        t += d;
    }
    return -1.0;
}

//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
// 3) Full BVH‐based ray tracer: returns first hit distance or MAX_DIST
//––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––––
float traceBVH(vec3 ro, vec3 rd) {
    // Early exit for degenerate rays
    if (dot(rd, rd) < 0.0001) return MAX_DIST_TO_TRAVEL;

    float tHit = MAX_DIST_TO_TRAVEL;

    // Fixed-size stack for traversal
    const int maxStackSize = 64;
    int stack[64];
    int stackPtr = 0;

    // Push root node
    stack[stackPtr++] = 0;

    // Main traversal loop - process until stack is empty
    while (stackPtr > 0) {
        // Pop node index from stack
        int nodeIdx = stack[--stackPtr];

        // Bounds check
        if (nodeIdx < 0 || nodeIdx >= nodes.length()) continue;

        // Fetch current node
        BVHNode node = nodes[nodeIdx];

        // Test ray against node's AABB
        vec3 boxMin = node.boundsMin.xyz;
        vec3 boxMax = node.boundsMax.xyz;

        // Skip invalid boxes
        if (any(lessThan(boxMax, boxMin))) continue;

        // Ray-box intersection
        vec2 tBox = intersectRayAABB(ro, rd, boxMin, boxMax);

        // Skip if no intersection or behind current closest hit
        if (tBox.x > tBox.y || tBox.y < 0.0 || tBox.x > tHit) continue;

        // Is this a leaf node?
        if (node.child.x < 0) {
            // It's a leaf - do sphere tracing within the box bounds
            float t0 = max(tBox.x, 0.0);    // Start at ray entry or origin
            float t1 = min(tBox.y, tHit);   // End at ray exit or current hit

            // Only trace if there's a valid segment
            if (t0 < t1) {
                float hitDist = sphereTraceSegment(ro, rd, t0, t1);
                if (hitDist > 0.0 && hitDist < tHit) {
                    tHit = hitDist;
                }
            }
        }
        else {
            // Not a leaf - process children
            int leftChild = node.child.x;
            int rightChild = node.child.y;

            // Make sure indices are valid
            if (leftChild >= 0 && leftChild < nodes.length() &&
            rightChild >= 0 && rightChild < nodes.length()) {

                // Process children in near-to-far order
                // First get the entry distances for both children
                BVHNode leftNode = nodes[leftChild];
                BVHNode rightNode = nodes[rightChild];

                vec2 leftBox = intersectRayAABB(ro, rd, leftNode.boundsMin.xyz, leftNode.boundsMax.xyz);
                vec2 rightBox = intersectRayAABB(ro, rd, rightNode.boundsMin.xyz, rightNode.boundsMax.xyz);

                float leftDist = leftBox.x;
                float rightDist = rightBox.x;

                // Check if we should even consider these nodes
                bool traverseLeft = leftBox.x <= leftBox.y && leftBox.y >= 0.0 && leftBox.x < tHit;
                bool traverseRight = rightBox.x <= rightBox.y && rightBox.y >= 0.0 && rightBox.x < tHit;

                // Push in reverse order (farther first, so nearest gets processed first)
                if (leftDist > rightDist) {
                    // Right is closer, push left first (processed second)
                    if (traverseLeft && stackPtr < maxStackSize) stack[stackPtr++] = leftChild;
                    if (traverseRight && stackPtr < maxStackSize) stack[stackPtr++] = rightChild;
                } else {
                    // Left is closer, push right first (processed second)
                    if (traverseRight && stackPtr < maxStackSize) stack[stackPtr++] = rightChild;
                    if (traverseLeft && stackPtr < maxStackSize) stack[stackPtr++] = leftChild;
                }
            }
        }
    }

    return tHit;
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
    float dist = traceBVH(cameraPos, rayDir);

    // Initialize color
    float t = 0.5 * (1.0 + rayDir.y);
    vec3 color = mix(vec3(1.0), vec3(0.15, 0.3, 1.0), t);

    if (dist < MAX_DIST_TO_TRAVEL) {
        // Hit point
        vec3 hitPos = cameraPos + rayDir * dist;

        // Get object ID that was hit
        float objectID = calcSDF(hitPos).y;

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

    // 3) add micro-dither to suppress any residual posterization
//    float d = (fract(sin(dot(gl_FragCoord.xy,vec2(12.9898,78.233))) * 43758.5453) - 0.5) / 255.0;
//    color += d;

    // Gamma correction
    color = pow(color, vec3(1.0/2.2));

    // Output final color
    FragColor = vec4(color, 1.0);
}