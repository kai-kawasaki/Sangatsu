#version 430 core
#include "hg_sdf.glsl"

in vec3 color;
layout (location = 0) out vec4 FragColor;

// Core SDF primitive types and operations (assumed from the included hg_sdf.glsl)
// Constants for rendering
const float MAX_STEPS = 500.0;
const float MIN_DIST_TO_SDF = 0.001;
const float MAX_DIST_TO_TRAVEL = 100.0;
const float EPSILON = 0.001;
const float LOD_MULTIPLIER = 0.06;
//const float PI = 3.14159265359;

// Object structure with added displacement fields
struct Object {
    float x, y, z;   // position
    float r, g, b;   // color
    float i, j, k;   // scale
    int objectType;
    int operation;
    float blendRadius;
    int groupLength;
    int materialID;
    int textureXY;
    int textureXZ;
    int textureYZ;
    float textureScale;
// PBR texture layers
    int albedoID;
    int normalID;
    int metallicID;
    int roughnessID;
    int aoID;
    int heightID;
// Displacement parameters
    float displacementStrength; // Scale of displacement effect
    int displacementMode;       // 0=none, 1=height-based, 2=adaptive, 3=vector-field
};

// Buffer bindings
layout (std430, binding = 0) buffer VisibleObjects {
    Object visibleObjects[];
};

layout (std430, binding = 1) buffer AllObjects {
    Object allObjects[];
};

// Uniforms
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_scroll;
uniform vec3 u_camPos;
uniform vec3 u_camTarget;
uniform int u_flashlight;
uniform int u_renderMode;
uniform int u_countObjects;
uniform sampler2DArray textureArray;

// Light structure
struct Light {
    float size;
    vec3 pos;
    vec3 col;
    vec3 dir;
    float focus;
    float spread;
};

// Light array uniforms
const int MAX_LIGHTS = 8;  // Define a reasonable maximum
uniform int u_lightCount;
uniform Light u_lights[MAX_LIGHTS];

// PBR material maps
struct PBRMaps {
    vec3 albedo;
    vec3 normalRGB;
    float metallic, roughness, ao, height;
};

// Displacement cache for performance optimization
struct DisplacementCache {
    float minHeight;      // Minimum height value in texture
    float maxHeight;      // Maximum height value in texture
    float avgHeight;      // Average height value
    float heightRange;    // Range from min to max
    float avgGradient;    // Average gradient magnitude (for step size control)
};

// Forward declarations of functions
float getObject(Object object, vec3 pos, float distFromCamera);
vec2 calcSDF(vec3 pos, bool cull);
vec3 calcNormal(vec3 p, float epsilon);
vec3 getLightPBR(vec3 hitPos, vec3 rayDir, float objectID);
vec3 getLightPhong(vec3 hitPos, vec3 rayDir, float objectID);
vec3 rCam(vec2 uv);
float calcShadow(vec3 origin, vec3 direction, float lightRadius);
void createTBN(vec3 normal, out vec3 tangent, out vec3 bitangent);

//------------------------------------------------------------------
// DISPLACEMENT MAPPING FUNCTIONS
//------------------------------------------------------------------

// Estimate normal for a primitive - used in displacement calculations
vec3 estimateNormal(vec3 p, Object obj) {
    vec3 location = vec3(obj.x, obj.y, obj.z);
    vec3 baseNormal;
    vec3 d;

    // Analytical normal based on primitive type
    switch (obj.objectType) {
        case 0: // Box
        d = p - location;
        vec3 s = vec3(obj.i, obj.j, obj.k);

        vec3 a = abs(d) - s;
        float maxComp = max(a.x, max(a.y, a.z));

        if (maxComp == a.x) baseNormal = vec3(sign(d.x), 0.0, 0.0);
        else if (maxComp == a.y) baseNormal = vec3(0.0, sign(d.y), 0.0);
        else baseNormal = vec3(0.0, 0.0, sign(d.z));
        break;

        case 1: // Sphere
        baseNormal = normalize(p - location);
        break;

        case 2: // Cylinder
        d = p - location;
        baseNormal = normalize(vec3(d.x, 0.0, d.z));
        break;

        case 3: // Cone
        // Simplified cone normal approximation
        d = p - location;
        float angle = atan(obj.j / obj.i);
        vec2 q = vec2(length(d.xz), d.y);
        baseNormal = normalize(vec3(q.x * cos(angle), sin(angle), q.x * sin(angle)));
        break;

        case 10: // Menger - use numerical for complex shapes
        default:
        // Use numerical normal WITHOUT calling getObject
        vec2 e = vec2(EPSILON, 0.0);
        vec3 location = vec3(obj.x, obj.y, obj.z);

        // Calculate base SDF directly without recursion
        float baseDist;
        vec3 pos = p;

        // Handle only the base object type without displacement
        switch (obj.objectType) {
            case 0:
            baseDist = fBox(pos-location, vec3(obj.i, obj.j, obj.k));
            break;
            case 1:
            baseDist = fSphere(pos-location, obj.i);
            break;
            case 2:
            baseDist = fCylinder(pos-location, obj.i, obj.j);
            break;
            case 3:
            baseDist = fCone(pos-location, obj.i, obj.j);
            break;
            case 10:
            baseDist = fMenger(pos-location, 5, obj.i);
            break;
            default:
            baseDist = 0.0;
        }

        // Calculate direct SDF values at offset points
        float dx, dy, dz;
        pos = p - e.xyy;
        switch (obj.objectType) {
            case 0: dx = fBox(pos-location, vec3(obj.i, obj.j, obj.k)); break;
            case 1: dx = fSphere(pos-location, obj.i); break;
            case 2: dx = fCylinder(pos-location, obj.i, obj.j); break;
            case 3: dx = fCone(pos-location, obj.i, obj.j); break;
            case 10: dx = fMenger(pos-location, 5, obj.i); break;
            default: dx = 0.0;
        }

        pos = p - e.yxy;
        switch (obj.objectType) {
            case 0: dy = fBox(pos-location, vec3(obj.i, obj.j, obj.k)); break;
            case 1: dy = fSphere(pos-location, obj.i); break;
            case 2: dy = fCylinder(pos-location, obj.i, obj.j); break;
            case 3: dy = fCone(pos-location, obj.i, obj.j); break;
            case 10: dy = fMenger(pos-location, 5, obj.i); break;
            default: dy = 0.0;
        }

        pos = p - e.yyx;
        switch (obj.objectType) {
            case 0: dz = fBox(pos-location, vec3(obj.i, obj.j, obj.k)); break;
            case 1: dz = fSphere(pos-location, obj.i); break;
            case 2: dz = fCylinder(pos-location, obj.i, obj.j); break;
            case 3: dz = fCone(pos-location, obj.i, obj.j); break;
            case 10: dz = fMenger(pos-location, 5, obj.i); break;
            default: dz = 0.0;
        }

        baseNormal = normalize(vec3(
        baseDist - dx,
        baseDist - dy,
        baseDist - dz
        ));
        break;
    }

    return baseNormal;
}

// Tri-planar mapping for height map sampling
float sampleDisplacement(vec3 p, vec3 normal, int heightMapID, float scale) {
    if (heightMapID < 0) return 0.0;

    // Transform into texture space
    vec3 pp = p * (1.0/scale);

    // Compute blend weights
    vec3 w = abs(normal);
    w = pow(w, vec3(5.0));
    w /= (w.x + w.y + w.z);

    // --- XY plane (+Z/–Z faces) ---
    vec2 uvXY = pp.xy * 0.5 + 0.5;
    if (normal.z < 0.0) {
        uvXY.x = 1.0 - uvXY.x;
    }
    uvXY.y = 1.0 - uvXY.y;

    // --- XZ plane (+Y/–Y faces) ---
    vec2 uvXZ = vec2(pp.x, pp.z) * 0.5 + 0.5;
    if (normal.y < 0.0) {
        uvXZ.x = 1.0 - uvXZ.x;
    }

    // --- YZ plane (+X/–X faces) ---
    vec2 uvYZ = vec2(pp.z, pp.y) * 0.5 + 0.5;
    if (normal.x < 0.0) {
        uvYZ.x = 1.0 - uvYZ.x;
    }
    uvYZ.y = 1.0 - uvYZ.y;

    // Sample height maps from each plane
    float hXY = texture(textureArray, vec3(uvXY, heightMapID)).r;
    float hXZ = texture(textureArray, vec3(uvXZ, heightMapID)).r;
    float hYZ = texture(textureArray, vec3(uvYZ, heightMapID)).r;

    // Blend based on normal direction
    return hXY * w.z + hXZ * w.y + hYZ * w.x;
}

// Displacement modes implementation

// Mode 1: Basic height-based displacement
float displacementHeight(Object obj, vec3 p, vec3 normal) {
    if (obj.heightID < 0 || obj.displacementStrength <= 0.0) return 0.0;

    float height = sampleDisplacement(p, normal, obj.heightID, obj.textureScale);
    // Remap from [0,1] to [-0.5,0.5]
    return (height - 0.5) * obj.displacementStrength;
}

// Mode 2: Adaptive displacement with LOD control
float displacementAdaptive(Object obj, vec3 p, vec3 normal, float distFromCamera) {
    if (obj.heightID < 0 || obj.displacementStrength <= 0.0) return 0.0;

    // LOD control - reduce displacement detail for distant objects
    float lodFactor = 1.0 - clamp(distFromCamera / MAX_DIST_TO_TRAVEL, 0.0, 0.95);

    // Calculate mip level based on distance (approximate)
    float mipLevel = floor(4.0 * (1.0 - lodFactor)); // 0-4 mip levels

    // We would ideally use textureGrad or textureLod here if supported
    float height = sampleDisplacement(p, normal, obj.heightID, obj.textureScale);

    // Apply displacement with distance-based attenuation
    return (height - 0.5) * obj.displacementStrength * lodFactor;
}

// Mode 3: Vector displacement - more advanced than height-based
vec3 displacementVector(Object obj, vec3 p, vec3 normal) {
    if (obj.heightID < 0 || obj.displacementStrength <= 0.0) return vec3(0.0);

    // In vector displacement, we use all 3 channels of the texture (RGB)
    // to represent displacement in tangent space

    // This is a simplified version - ideally we'd sample each RGB channel separately
    float dispX = sampleDisplacement(p, normal, obj.heightID, obj.textureScale) - 0.5;
    float dispY = sampleDisplacement(p, normal, obj.heightID+1, obj.textureScale) - 0.5; // Next texture in array
    float dispZ = sampleDisplacement(p, normal, obj.heightID+2, obj.textureScale) - 0.5; // Next+1 texture

    // Create a tangent space from the normal
    vec3 tangent, bitangent;
    createTBN(normal, tangent, bitangent);

    // Transform displacement from tangent space to world space
    return (tangent * dispX + normal * dispY + bitangent * dispZ) * obj.displacementStrength;
}

// Integrated displacement function
float applyDisplacement(Object obj, vec3 p, float baseDist, float distFromCamera) {
    if (obj.displacementMode == 0 || obj.heightID < 0 || obj.displacementStrength <= 0.0) {
        return baseDist; // No displacement
    }

    vec3 normal = estimateNormal(p, obj);
    float displacement = 0.0;

    switch (obj.displacementMode) {
        case 1: // Basic height displacement
        displacement = displacementHeight(obj, p, normal);
        break;

        case 2: // Adaptive LOD displacement
        displacement = displacementAdaptive(obj, p, normal, distFromCamera);
        break;

        case 3: { // Vector displacement
            vec3 dispVec = displacementVector(obj, p, normal);
            // Project displacement onto SDF gradient direction (approximated by normal)
            displacement = dot(dispVec, normal);
            break;
        }
    }

    return baseDist - displacement;
}

//------------------------------------------------------------------
// CORE SDF FUNCTIONS
//------------------------------------------------------------------

// Main SDF function with displacement
float getObject(Object object, vec3 pos, float distFromCamera) {
    // First get the base SDF value
    vec3 location = vec3(object.x, object.y, object.z);
    float baseDist;

    switch (object.objectType) {
        case 0:
        baseDist = fBox(pos-location, vec3(object.i, object.j, object.k));
        break;
        case 1:
        baseDist = fSphere(pos-location, object.i);
        break;
        case 2:
        baseDist = fCylinder(pos-location, object.i, object.j);
        break;
        case 3:
        baseDist = fCone(pos-location, object.i, object.j);
        break;
        case 10:
        baseDist = fMenger(pos-location, 5, object.i);
        break;
        default:
        return 0.0;
    }

    // Apply displacement if enabled
    if (object.displacementMode > 0 && object.heightID >= 0 && object.displacementStrength > 0.0) {
        baseDist = applyDisplacement(object, pos, baseDist, distFromCamera);
    }

    return baseDist;
}

// Calculate scene SDF - minimum distance to any object
vec2 calcSDF(vec3 pos, bool cull) {
    vec2 sceneDist = vec2(MAX_DIST_TO_TRAVEL, -1.0);
    float distFromCamera = length(pos - u_camPos);

    if (cull) {
        int i = 0;
        while (i < u_countObjects) {
            // head of this group
            Object head = visibleObjects[i];
            int glen = head.groupLength;
            int last = min(i + glen, u_countObjects - 1);

            // --- initialize accumulator from the first object in the group ---
            float d0 = getObject(visibleObjects[i], pos, distFromCamera);
            float da = d0;

            // --- accumulate influence of the rest of the group ---
            for (int j = i + 1; j <= last && j < u_countObjects; j++) {
                float dj = getObject(visibleObjects[j], pos, distFromCamera);

                if (visibleObjects[j].operation == 0) {
                    // Union
                    if (visibleObjects[j].blendRadius > 0.0) {
                        da = opSmoothUnion(da, dj, visibleObjects[j].blendRadius);
                    } else {
                        da = opUnion(da, dj);
                    }
                } else if (visibleObjects[j].operation == 1) {
                    // Subtraction
                    if (visibleObjects[j].blendRadius > 0.0) {
                        da = opSmoothSubtraction(dj, da, visibleObjects[j].blendRadius);
                    } else {
                        da = opSubtraction(dj, da);
                    }
                } else if (visibleObjects[j].operation == 2) {
                    // Intersection
                    if (visibleObjects[j].blendRadius > 0.0) {
                        da = opSmoothIntersection(da, dj, visibleObjects[j].blendRadius);
                    } else {
                        da = opIntersection(da, dj);
                    }
                }
            }

            // --- check if this group is the closest so far ---
            if (da < sceneDist.x) {
                sceneDist.x = da;
                sceneDist.y = float(i); // Store object ID of the group head
            }

            i = last + 1;
        }
    }

    return sceneDist;
}

// Enhanced normal calculation for displaced surfaces
vec3 calcNormal(vec3 p, float epsilon) {
    // Determine the closest object for accurate normal calculation
    vec2 sdfResult = calcSDF(p, true);
    int objID = int(sdfResult.y);

    // If we have a valid object with displacement, use a specialized approach
    if (objID >= 0 && objID < visibleObjects.length()) {
        Object obj = visibleObjects[objID];

        if (obj.displacementMode > 0 && obj.heightID >= 0) {
            // For displaced surfaces, use a smaller epsilon and consider displacement variation
            float smallerEpsilon = epsilon * 0.5;
            float distFromCamera = length(p - u_camPos);

            // Forward difference approximation
            vec2 e = vec2(smallerEpsilon, 0.0);

            // Sample the SDF at offset positions
            float center = sdfResult.x;
            float dx = getObject(obj, p + e.xyy, distFromCamera);
            float dy = getObject(obj, p + e.yxy, distFromCamera);
            float dz = getObject(obj, p + e.yyx, distFromCamera);

            // Create a more precise normal for displaced surfaces
            return normalize(vec3(
            dx - center,
            dy - center,
            dz - center
            ));
        }
    }

    // Fall back to standard normal calculation for non-displaced surfaces
    vec2 e = vec2(epsilon, 0);
    float d = calcSDF(p, true).x;
    vec3 n = vec3(
    calcSDF(p + e.xyy, true).x - d,
    calcSDF(p + e.yxy, true).x - d,
    calcSDF(p + e.yyx, true).x - d
    );
    return normalize(n);
}

//------------------------------------------------------------------
// RAY MARCHING AND RENDERING
//------------------------------------------------------------------

// Enhanced ray marching with better convergence near surfaces
float rMarch(vec3 rOrig, vec3 rDir) {
    float dOrig = 0.0;
    float relaxation = 1.0;
    float lastMinDist = MAX_DIST_TO_TRAVEL;

    for(int i=0; i<MAX_STEPS; i++) {
        vec3 rPos = rOrig + rDir * dOrig;
        vec2 sdfResult = calcSDF(rPos, true);
        float dSurf = sdfResult.x;
        int objID = int(sdfResult.y);

        // For objects with displacement, use more conservative steps
        if (objID >= 0 && objID < visibleObjects.length()) {
            Object obj = visibleObjects[objID];
            if (obj.displacementMode > 0 && obj.heightID >= 0) {
                // Use stricter relaxation for displaced surfaces
                relaxation = 0.5;

                // If we're close to the surface, use even smaller steps
                if (abs(dSurf) < 0.1) {
                    relaxation = 0.25;
                }
            } else {
                relaxation = 0.9;
            }
        } else {
            relaxation = 1.0;
        }

        // Track if we're overshooting (distance increases after decreasing)
        if (dSurf > lastMinDist && lastMinDist < 0.1) {
            // We might have overshot a thin feature, take smaller steps
            relaxation = 0.1;
        }
        lastMinDist = min(lastMinDist, dSurf);

        // Apply relaxation factor to step size
        float step = dSurf * relaxation;

        // Minimum step size to prevent getting stuck
        step = max(step, MIN_DIST_TO_SDF * 0.1);

        dOrig += step;

        // Progressive hit threshold - larger for distant objects
        float hitThreshold = MIN_DIST_TO_SDF * (1.0 + 0.01 * dOrig);

        if(abs(dSurf) < hitThreshold || dOrig > MAX_DIST_TO_TRAVEL) break;
    }

    return dOrig;
}

// Helper function for shadow calculation with displacement awareness
float calcShadow(vec3 origin, vec3 direction, float lightRadius) {
    float minShadow = 1.0;
    float maxDistance = 20.0;
    float t = 0.1; // Start a little away from the surface

    // Offset origin slightly to avoid self-shadowing
    origin += direction * 0.01;

    for (int i = 0; i < 32; i++) {
        vec3 pos = origin + direction * t;
        vec2 res = calcSDF(pos, true);
        float h = res.x;

        // Get the object ID to check if it has displacement
        int objID = int(res.y);
        float penumbra = 1.0;

        if (objID >= 0 && objID < visibleObjects.length()) {
            Object obj = visibleObjects[objID];
            if (obj.displacementMode > 0 && obj.heightID >= 0) {
                // Use larger penumbra for objects with displacement
                penumbra = 4.0;
            }
        }

        // Soft shadows with penumbra
        float y = h*h/(2.0*t);
        float d = sqrt(h*h-y*y);

        minShadow = min(minShadow, penumbra * d / max(0.0, t - y));

        // Early termination
        if (minShadow < 0.001 || t >= maxDistance) break;

        // Adaptive step size based on distance
        t += clamp(h, 0.01, 0.5);
    }

    return clamp(minShadow, 0.0, 1.0);
}

//------------------------------------------------------------------
// PBR LIGHTING FUNCTIONS
//------------------------------------------------------------------

// Create a helper function to build TBN matrix for normal mapping
void createTBN(vec3 normal, out vec3 tangent, out vec3 bitangent) {
    // Create a tangent that's perpendicular to the normal
    vec3 upVector = abs(normal.y) > 0.99 ? vec3(0, 0, 1) : vec3(0, 1, 0);
    tangent = normalize(cross(upVector, normal));
    bitangent = normalize(cross(normal, tangent));
}

// PBR helper functions
float distributionGGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH2 = NdotH * NdotH;

    float denom = NdotH2 * (a2 - 1.0) + 1.0;
    denom = PI * denom * denom;

    return a2 / max(denom, 0.0001);
}

float geometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;

    return NdotV / (NdotV * (1.0 - k) + k);
}

float geometrySmith(float NdotV, float NdotL, float roughness) {
    return geometrySchlickGGX(NdotV, roughness) * geometrySchlickGGX(NdotL, roughness);
}

vec3 fresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// ACES Filmic Tone Mapping (for HDR rendering)
vec3 ACESFilmicTone(vec3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// Fog effect with improved handling for displaced surfaces
vec3 applyFog(vec3 color, float distance, vec3 rayDir, vec3 sunDir) {
    float fogAmount = 1.0 - exp(-distance * 0.02);

    // Directional scattering (more light in the direction of the sun)
    float sunAmount = max(dot(rayDir, sunDir), 0.0);
    vec3 fogColor = mix(
    vec3(0.5, 0.6, 0.7), // Base fog color
    vec3(1.0, 0.9, 0.7), // Sun-scattered fog color
    pow(sunAmount, 8.0)
    );

    return mix(color, fogColor, fogAmount);
}

vec2 getUV(vec2 offset) {
    return ((gl_FragCoord.xy + offset) - 0.5 * u_resolution.xy) / u_resolution.y;
}

// Camera ray from screen UV
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


// Phong shading
vec3 getLightPhong(vec3 hitPos, vec3 rayDir, float objectID) {
    // fetch object color
    Object obj = visibleObjects[int(objectID)];
    vec3 N = calcNormal(hitPos, EPSILON);
    vec3 V = normalize(-rayDir);
    vec3 colorOut = vec3(0.0);
    // ambient
    vec3 ambient = 0.1 * vec3(obj.r, obj.g, obj.b);
    colorOut += ambient;
    // loop over lights
    for(int i = 0; i < u_lightCount; ++i) {
        Light L = u_lights[i];
        vec3 Ldir = normalize(L.pos - hitPos);
        float diff = max(dot(N, Ldir), 0.0);
        vec3 diffuse = diff * L.col * vec3(obj.r, obj.g, obj.b);
        // specular
        vec3 H = normalize(Ldir + V);
        float spec = pow(max(dot(N, H), 0.0), 16.0);
        vec3 specular = spec * L.col;
        // accumulate with attenuation
        float attenuation = 1.0 / (1.0 + 0.1 * length(L.pos - hitPos));
        colorOut += attenuation * (diffuse + specular);
    }
    return colorOut;
}

// Tri-planar sampling for textureArray
vec3 triPlanarArray(sampler2DArray texArr, vec3 p, vec3 normal, float scale, int layer) {
    vec3 pp = p / scale;
    vec3 w = abs(normal);
    w = pow(w, vec3(5.0));
    w /= (w.x + w.y + w.z);
    // xy
    vec2 uvXY = pp.xy * 0.5 + 0.5;
    if(normal.z < 0.0) uvXY.x = 1.0 - uvXY.x;
    // xz
    vec2 uvXZ = pp.xz * 0.5 + 0.5;
    if(normal.y < 0.0) uvXZ.x = 1.0 - uvXZ.x;
    // yz
    vec2 uvYZ = pp.zy * 0.5 + 0.5;
    if(normal.x < 0.0) uvYZ.x = 1.0 - uvYZ.x;
    // sample
    vec3 cXY = texture(texArr, vec3(uvXY, layer)).rgb;
    vec3 cXZ = texture(texArr, vec3(uvXZ, layer)).rgb;
    vec3 cYZ = texture(texArr, vec3(uvYZ, layer)).rgb;
    return cXY * w.z + cXZ * w.y + cYZ * w.x;
}

// PBR shading (Cook-Torrance)
vec3 getLightPBR(vec3 hitPos, vec3 rayDir, float objectID) {
    Object obj    = visibleObjects[int(objectID)];
    // 1) Base analytic normal
    vec3 N_analytic = calcNormal(hitPos, EPSILON);

    // 2) Sample and decode the normal map
    vec3 normalRGB   = triPlanarArray(textureArray, hitPos, N_analytic, obj.textureScale, obj.normalID);
    vec3 nTangent    = normalize(normalRGB * 2.0 - 1.0);

    // 3) Build TBN & transform to world-space normal
    vec3 T, B;
    createTBN(N_analytic, T, B);
    vec3 N = normalize( T * nTangent.x +
    B * nTangent.y +
    N_analytic * nTangent.z );

    vec3 V = normalize(-rayDir);

    // 4) Sample all material maps via tri-planar
    vec3 albedo    = triPlanarArray(textureArray, hitPos, N, obj.textureScale, obj.albedoID);
    float metallic = triPlanarArray(textureArray, hitPos, N, obj.textureScale, obj.metallicID).r;
    float roughness= triPlanarArray(textureArray, hitPos, N, obj.textureScale, obj.roughnessID).r;
    float ao       = triPlanarArray(textureArray, hitPos, N, obj.textureScale, obj.aoID).r;

    // 5) Precompute F0
    vec3 F0 = mix(vec3(0.04), albedo, metallic);

    vec3 Lo = vec3(0.0);
    for(int i = 0; i < u_lightCount; ++i) {
        Light L = u_lights[i];
        vec3 Ldir = normalize(L.pos - hitPos);
        vec3 H    = normalize(V + Ldir);

        float NdotL = max(dot(N, Ldir), 0.0);
        float NdotV = max(dot(N, V),    0.0);
        float NdotH = max(dot(N, H),    0.0);
        float VdotH = max(dot(V, H),    0.0);

        float D = distributionGGX(NdotH, roughness);
        float G = geometrySmith(NdotV, NdotL, roughness);
        vec3  F = fresnelSchlick(VdotH, F0);

        vec3 spec = (D * G * F) / max(4.0 * NdotV * NdotL, 0.001);
        vec3 kS   = F;
        vec3 kD   = (1.0 - kS) * (1.0 - metallic);

        float attenuation = 1.0 / dot(L.pos - hitPos, L.pos - hitPos);
        vec3 irradiance   = L.col * attenuation * NdotL;

        Lo += (kD * albedo / PI + spec) * irradiance;
    }

    // 6) Ambient + AO
    vec3 ambient = vec3(0.03) * albedo * ao;

    return ambient + Lo;
}


//------------------------------------------------------------------
// MAIN FUNCTION
//------------------------------------------------------------------

void main() {
    // Compute ray direction for this fragment
    vec2 uv = (gl_FragCoord.xy / u_resolution.xy) * 2.0 - 1.0;
    uv.x *= u_resolution.x / u_resolution.y; // Aspect ratio correction

    // Camera setup
    vec3 cameraPos = u_camPos;
    vec3 rayDir = rCam(uv);

    // Enhanced ray marching with displacement support
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
        color = mix(vec3(1.0), vec3(0.5, 0.7, 1.0), t);
    }

    // Tone mapping
    color = ACESFilmicTone(color);

    // Micro-dither to reduce banding
    float d = (fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
    color += d;

    // Gamma correction
    color = pow(color, vec3(1.0/2.2));

    // Output final color
    FragColor = vec4(color, 1.0);
}

// Note: This implementation assumes additional functions like getLightPhong, getLightPBR, and rCam
// are defined elsewhere in your codebase, along with proper tri-planar mapping for PBR textures.