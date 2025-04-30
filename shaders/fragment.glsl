#version 430 core
#include "hg_sdf.glsl"

in vec3 color;
layout (location = 0) out vec4 FragColor;

struct Object {
    float x, y, z;        // position
    float r, g, b;        // color
    float i, j, k;        // scale
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
};

layout (std430, binding = 0) buffer VisibleObjects {
    Object visibleObjects[];
};

layout (std430, binding = 1) buffer AllObjects {
    Object allObjects[];
};

precision mediump float;

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_scroll;
uniform vec3 u_camPos;
uniform vec3 u_camTarget;
uniform int u_flashlight;
uniform int u_renderMode;
uniform int u_countObjects;

uniform sampler2DArray textureArray;

// Constants
const float DISPLACEMENT_STRENGTH = 0.2;
const float MAX_STEPS = 500.0;
const float MIN_DIST_TO_SDF = 0.001;
const float MAX_DIST_TO_TRAVEL = 100.0;
const float EPSILON = 0.001;
const float LOD_MULTIPLIER = 0.06;

struct Light {
    float size;
    vec3 pos;
    vec3 col;
    vec3 dir;
    float focus;
    float spread;
};

// PBR structure to hold all material maps
struct PBRMaps {
    vec3 albedo;
    vec3 normalRGB;
    float metallic, roughness, ao, height;
};

// Function declarations
vec2 minID(vec2 res1, vec2 res2);
float getObjectRaw(Object object, vec3 pos);
float getObject(Object object, vec3 pos);
vec2 maxID(vec2 a, vec2 b);
vec2 calcSDF(vec3 pos, bool cull);
vec3 getPrimitiveNormal(Object object, vec3 pos);

vec3 triPlanar(sampler2D tex, vec3 p, vec3 normal, float size) {
    p*=(1.0/size);
    normal = abs(normal);
    normal = pow(normal, vec3(5.0));
    normal /= normal.x + normal.y + normal.z;
    return (texture(tex, p.xy * 0.5 + 0.5) * normal.z +
    texture(tex, p.xz * 0.5 + 0.5) * normal.y +
    texture(tex, p.yz * 0.5 + 0.5) * normal.x).rgb;
}

vec3 triPlanarArray(
sampler2DArray texArr,
vec3           p,
vec3           normal,
float          size,
vec3           layer    // three slice indices
) {
    vec3 pp = p * (1.0 / size);
    vec3 w  = abs(normal);
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
    if (normal.y > 0.0) {
        uvXZ.x = 1.0 - uvXZ.x;
    }

    // --- YZ plane (+X/–X faces) ---
    vec2 uvYZ = vec2(pp.z, pp.y) * 0.5 + 0.5;
    if (normal.x > 0.0) {
        uvYZ.x = 1.0 - uvYZ.x;
    }
    uvYZ.y = 1.0 - uvYZ.y;

    vec3 cXY = texture(texArr, vec3(uvXY, layer.z)).rgb;
    vec3 cXZ = texture(texArr, vec3(uvXZ, layer.y)).rgb;
    vec3 cYZ = texture(texArr, vec3(uvYZ, layer.x)).rgb;

    return cXY * w.z
    + cXZ * w.y
    + cYZ * w.x;
}

// New PBR tri-planar mapping with parallax
// Improved tri-planar mapping for PBR with corrected face orientations
PBRMaps triPlanarPBR(
sampler2DArray arr,
vec3           p,
vec3           n,
float          scale,
int            albedoLayer,
int            normalLayer,
int            metallicLayer,
int            roughnessLayer,
int            aoLayer,
int            heightLayer,
vec3           viewDir   // for parallax
) {
    // 1) Transform into texture-space
    vec3 pp = p * (1.0/scale);

    // 2) Compute blend weights for smooth transitions between faces
    vec3 w = abs(n);
    w = pow(w, vec3(5.0));
    w /= (w.x + w.y + w.z);

    // 3) UVs per plane - FIXED for correct orientation

    // --- XY plane (+Z/–Z faces) ---
    vec2 uvXY = pp.xy * 0.5 + 0.5;
    // For front face (+Z), standard UV
    // For back face (-Z), flip X coordinate
    if (n.z < 0.0) {
        uvXY.x = 1.0 - uvXY.x;
    }
    // Always flip Y in texture space
    uvXY.y = 1.0 - uvXY.y;

    // --- XZ plane (+Y/–Y faces) ---
    vec2 uvXZ = vec2(pp.x, pp.z) * 0.5 + 0.5;
    // For bottom face (-Y), standard UV
    // For top face (+Y), flip X coordinate - THIS WAS BACKWARDS!
    if (n.y < 0.0) { // FIXED: Changed from > to <
        uvXZ.x = 1.0 - uvXZ.x;
    }

    // --- YZ plane (+X/–X faces) ---
    vec2 uvYZ = vec2(pp.z, pp.y) * 0.5 + 0.5;
    // For right face (+X), standard UV
    // For left face (-X), flip X coordinate
    if (n.x < 0.0) { // FIXED: Changed from > to <
        uvYZ.x = 1.0 - uvYZ.x;
    }
    // Always flip Y in texture space
    uvYZ.y = 1.0 - uvYZ.y;

    // 4) Debug weights - uncomment to diagnose face mapping
    // Output weights as colors to check orientation
    /*
    PBRMaps debug;
    debug.albedo = vec3(w.x, w.y, w.z);
    debug.normalRGB = vec3(0.5, 0.5, 1.0);
    debug.metallic = 0.0;
    debug.roughness = 0.5;
    debug.ao = 1.0;
    debug.height = 0.0;
    return debug;
    */

    // 4) Parallax occlusion on each UV if height map is provided
    if (heightLayer >= 0) {
        float hXY = texture(arr, vec3(uvXY, heightLayer)).r;
        float hXZ = texture(arr, vec3(uvXZ, heightLayer)).r;
        float hYZ = texture(arr, vec3(uvYZ, heightLayer)).r;

        // Project viewDir into each plane
        vec2 vXY = normalize(viewDir.xy);
        vec2 vXZ = normalize(viewDir.xz);
        vec2 vYZ = normalize(viewDir.yz);

        // Apply parallax offset
        float parallaxScale = 0.05 * scale; // Adjust parallax strength
        uvXY = uvXY - vXY * (hXY * parallaxScale / max(dot(n, viewDir), 0.01));
        uvXZ = uvXZ - vXZ * (hXZ * parallaxScale / max(dot(n, viewDir), 0.01));
        uvYZ = uvYZ - vYZ * (hYZ * parallaxScale / max(dot(n, viewDir), 0.01));
    }

    // 5) Initialize PBR maps
    PBRMaps m;

    // Sample and blend each map (only if valid layer ID)
    m.albedo = (albedoLayer >= 0) ?
    texture(arr, vec3(uvXY, albedoLayer)).rgb * w.z +
    texture(arr, vec3(uvXZ, albedoLayer)).rgb * w.y +
    texture(arr, vec3(uvYZ, albedoLayer)).rgb * w.x :
    vec3(1.0);

    m.normalRGB = (normalLayer >= 0) ?
    texture(arr, vec3(uvXY, normalLayer)).rgb * w.z +
    texture(arr, vec3(uvXZ, normalLayer)).rgb * w.y +
    texture(arr, vec3(uvYZ, normalLayer)).rgb * w.x :
    vec3(0.5, 0.5, 1.0);

    m.metallic = (metallicLayer >= 0) ?
    texture(arr, vec3(uvXY, metallicLayer)).r * w.z +
    texture(arr, vec3(uvXZ, metallicLayer)).r * w.y +
    texture(arr, vec3(uvYZ, metallicLayer)).r * w.x :
    0.0;

    m.roughness = (roughnessLayer >= 0) ?
    texture(arr, vec3(uvXY, roughnessLayer)).r * w.z +
    texture(arr, vec3(uvXZ, roughnessLayer)).r * w.y +
    texture(arr, vec3(uvYZ, roughnessLayer)).r * w.x :
    0.5;

    m.ao = (aoLayer >= 0) ?
    texture(arr, vec3(uvXY, aoLayer)).r * w.z +
    texture(arr, vec3(uvXZ, aoLayer)).r * w.y +
    texture(arr, vec3(uvYZ, aoLayer)).r * w.x :
    1.0;

    m.height = (heightLayer >= 0) ?
    texture(arr, vec3(uvXY, heightLayer)).r * w.z +
    texture(arr, vec3(uvXZ, heightLayer)).r * w.y +
    texture(arr, vec3(uvYZ, heightLayer)).r * w.x :
    0.0;

    return m;
}

// Unpack normal map to [-1,1] range
vec3 unpackNormal(vec3 rgb) {
    return normalize(rgb * 2.0 - 1.0);
}

// Transform normal from tangent space to world space
// Targeted fix for triPlanarNormal function
vec3 triPlanarNormal(
vec3 geomNormal,
sampler2DArray arr,
vec3 p,
float scale,
int normalLayer,
vec3 viewDir
) {
    if (normalLayer < 0) {
        return geomNormal;
    }

    // Get absolute normal for face determination
    vec3 absN = abs(geomNormal);

    // Create weight for face blending
    vec3 w = absN;
    w = pow(w, vec3(5.0));
    w /= (w.x + w.y + w.z);

    // Transform position to texture space
    vec3 pp = p * (1.0/scale);

    // --- FACE 1: XY plane (Z normal) ---
    vec2 uvXY = pp.xy * 0.5 + 0.5;
    if (geomNormal.z < 0.0) {
        uvXY.x = 1.0 - uvXY.x; // Flip for back face
    }
    uvXY.y = 1.0 - uvXY.y; // Flip Y - texture convention

    // --- FACE 2: XZ plane (Y normal) ---
    vec2 uvXZ = vec2(pp.x, pp.z) * 0.5 + 0.5;
    if (geomNormal.y < 0.0) {
        uvXZ.x = 1.0 - uvXZ.x; // Flip for bottom face
    }

    // --- FACE 3: YZ plane (X normal) ---
    vec2 uvYZ = vec2(pp.z, pp.y) * 0.5 + 0.5;
    if (geomNormal.x < 0.0) {
        uvYZ.x = 1.0 - uvYZ.x; // Flip for left face
    }
    uvYZ.y = 1.0 - uvYZ.y; // Flip Y - texture convention

    // Sample normal maps
    vec3 tcNormalXY = texture(arr, vec3(uvXY, normalLayer)).rgb;
    vec3 tcNormalXZ = texture(arr, vec3(uvXZ, normalLayer)).rgb;
    vec3 tcNormalYZ = texture(arr, vec3(uvYZ, normalLayer)).rgb;

    // Unpack to -1 to 1 range
    vec3 tanNormalXY = tcNormalXY * 2.0 - 1.0;
    vec3 tanNormalXZ = tcNormalXZ * 2.0 - 1.0;
    vec3 tanNormalYZ = tcNormalYZ * 2.0 - 1.0;

    // Create proper tangent spaces for each face
    // CORRECTED: Fixed the tanget/bitangent orientations

    // For XY plane (Z normal)
    vec3 zTangent = normalize(vec3(1.0, 0.0, 0.0));
    vec3 zBitangent = normalize(vec3(0.0, 1.0, 0.0));
    vec3 zNormal = vec3(0.0, 0.0, sign(geomNormal.z));

    // For XZ plane (Y normal)
    vec3 yTangent = normalize(vec3(1.0, 0.0, 0.0));
    vec3 yBitangent = normalize(vec3(0.0, 0.0, 1.0));
    vec3 yNormal = vec3(0.0, sign(geomNormal.y), 0.0);

    // For YZ plane (X normal)
    vec3 xTangent = normalize(vec3(0.0, 0.0, 1.0));
    vec3 xBitangent = normalize(vec3(0.0, 1.0, 0.0));
    vec3 xNormal = vec3(sign(geomNormal.x), 0.0, 0.0);

    // Convert tangent space normal to world space normal
    // Using the tangent space basis vectors
    vec3 worldNormalXY = normalize(
    tanNormalXY.x * zTangent +
    tanNormalXY.y * zBitangent +
    tanNormalXY.z * zNormal
    );

    vec3 worldNormalXZ = normalize(
    tanNormalXZ.x * yTangent +
    tanNormalXZ.y * yBitangent +
    tanNormalXZ.z * yNormal
    );

    vec3 worldNormalYZ = normalize(
    tanNormalYZ.x * xTangent +
    tanNormalYZ.y * xBitangent +
    tanNormalYZ.z * xNormal
    );

    // KEY FIX: Ensure the XY plane (Z normal) is emphasized instead of YZ plane
    // Swap weighting between X and Z components to prioritize XY plane
    vec3 fixedWeights = vec3(w.z, w.y, w.x);

    // Combine with weights - using the FIXED weights
    vec3 finalNormal = normalize(
    worldNormalXY * fixedWeights.x +
    worldNormalXZ * fixedWeights.y +
    worldNormalYZ * fixedWeights.z
    );

    return finalNormal;
}

// PBR Functions
float DistributionGGX(vec3 N, vec3 H, float roughness) {
    float a = roughness*roughness;
    float a2 = a*a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;

    float nom   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float nom   = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return nom / denom;
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness) {
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

vec3 fresnelSchlick(float cosTheta, vec3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// Cook-Torrance BRDF
vec3 cookTorrance(vec3 N, vec3 V, vec3 L, vec3 albedo, float metallic, float roughness, float ao) {
    vec3 H = normalize(V + L);

    vec3 F0 = vec3(0.04);
    F0 = mix(F0, albedo, metallic);

    // Cook-Torrance BRDF
    float NDF = DistributionGGX(N, H, roughness);
    float G   = GeometrySmith(N, V, L, roughness);
    vec3  F   = fresnelSchlick(max(dot(H, V), 0.0), F0);

    vec3 numerator    = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.001; // prevent div by zero
    vec3 specular = numerator / denominator;

    // Diffuse contribution
    vec3 kS = F;
    vec3 kD = vec3(1.0) - kS;
    kD *= 1.0 - metallic;

    // Add to outgoing radiance Lo
    float NdotL = max(dot(N, L), 0.0);

    return (kD * albedo / PI + specular) * NdotL;
}

vec2 minID(vec2 res1, vec2 res2) {
    return (res1.x < res2.x) ? res1 : res2;
}

float getObjectRaw(Object object, vec3 pos) {
    // 0 = box
    // 1 = sphere
    // 2 = cylinder
    // 3 = cone
    // 4 = torus
    // 5 = plane
    // 6 = capsule
    // 7 = ellipsoid
    vec3 location = vec3(object.x, object.y, object.z);
    switch (object.objectType) {
        case 0:
        return fBox(pos-location, vec3(object.i, object.j, object.k));
        case 1:
        return fSphere(pos-location, object.i);
        case 2:
        return fCylinder(pos-location, object.i, object.j);
        case 3:
        return fCone(pos-location, object.i, object.j);
        case 10:
        return fMenger(pos-location, 5, object.i);
    }
    return 0.0;
}

vec3 getPrimitiveNormal(Object object, vec3 pos) {
    // choose a VERY small offset
    const float h = EPSILON;
    return normalize(vec3(
    getObjectRaw(object, pos + vec3( h, 0, 0))
    - getObjectRaw(object, pos - vec3( h, 0, 0)),
    getObjectRaw(object, pos + vec3( 0, h, 0))
    - getObjectRaw(object, pos - vec3( 0, h, 0)),
    getObjectRaw(object, pos + vec3( 0, 0, h))
    - getObjectRaw(object, pos - vec3( 0, 0, h))
    ));
}

// helper for intersection: pick the farthest distance, tracking ID
vec2 maxID(vec2 a, vec2 b) {
    return (a.x > b.x) ? a : b;
}

vec2 calcSDF(vec3 pos, bool cull) {
    vec2 sceneDist = vec2(MAX_DIST_TO_TRAVEL, -1.0);

    if (cull) {
        int i = 0;
        while (i < u_countObjects) {
            // head of this group
            Object head = visibleObjects[i];
            int glen = head.groupLength;
            int last = min(i + glen, u_countObjects - 1);

            // --- initialize accumulator from the first object in the group ---
            float d0 = getObject(head, pos);
            vec2 groupDist = vec2(d0, float(i));

            // --- fold in each of the remaining members j = i+1 .. last ---
            for (int j = i + 1; j <= last; ++j) {
                Object o = visibleObjects[j];
                float dj = getObject(o, pos);

                // choose the operation of this *member*, not the head
                switch (o.operation) {
                    case 0: {
                        // hard‐union = min(d1, d2)
                        float u = opUnion(groupDist.x, dj);
                        // whichever was nearer before union
                        float uID = (groupDist.x < dj) ? groupDist.y : float(j);
                        groupDist = vec2(u, uID);
                    } break;

                    case 1: {
                        // smooth‐union
                        float su = opSmoothUnion(groupDist.x, dj, o.blendRadius);
                        float suID = (groupDist.x < dj) ? groupDist.y : float(j);
                        groupDist = vec2(su, suID);
                    } break;

                    case 2: {
                        // hard‐intersection = max(d1, d2)
                        vec2 inter = maxID(vec2(dj, float(j)), groupDist);
                        groupDist = inter;
                    } break;

                    case 3: {
                        // smooth‐intersection
                        float si = opSmoothIntersection(groupDist.x, dj, o.blendRadius);
                        // whichever was "farther" before smoothing
                        float siID = (groupDist.x > dj) ? groupDist.y : float(j);
                        groupDist = vec2(si, siID);
                    } break;

                    case 4: {
                        // hard‐subtraction = max(-d1, d2)
                        float hs = opSubtraction(groupDist.x, dj);
                        // pick ID of the branch that set the max:
                        // if -d1 > d2, we keep the original; else we switch to j
                        float hsID = (-groupDist.x > dj) ? groupDist.y : float(j);
                        groupDist = vec2(hs, hsID);
                    } break;

                    case 5: {
                        // smooth‐subtraction
                        float ss = opSmoothSubtraction(groupDist.x, dj, o.blendRadius);
                        // pick the ID of whichever region "won" before smoothing:
                        // if original (d1) dominated, keep its ID; else use j
                        float ssID = (groupDist.x < -dj) ? groupDist.y : float(j);
                        groupDist = vec2(ss, ssID);
                    } break;

                    // add more cases here if you introduce new ops…
                }

            }

            // --- merge this group's result into the overall scene ---
            sceneDist = minID(groupDist, sceneDist);

            // advance to next group
            i = last + 1;
        }

    } else {
        // ——— non-culled path over allObjects ———
        int i = 0;
        while (i < allObjects.length()) {
            Object head = allObjects[i];
            int last = min(i + head.groupLength, allObjects.length() - 1);

            float d0 = getObject(head, pos);
            vec2 groupDist = vec2(d0, float(i));

            for (int j = i + 1; j <= last; ++j) {
                Object o = allObjects[j];
                float dj = getObject(o, pos);

                switch (o.operation) {
                    case 0: {
                        float u = opUnion(groupDist.x, dj);
                        float uID = (groupDist.x < dj) ? groupDist.y : float(j);
                        groupDist = vec2(u, uID);
                    } break;
                    case 1: {
                        float su = opSmoothUnion(groupDist.x, dj, o.blendRadius);
                        float suID = (groupDist.x < dj) ? groupDist.y : float(j);
                        groupDist = vec2(su, suID);
                    } break;
                    case 2: {
                        groupDist = maxID(vec2(dj, float(j)), groupDist);
                    } break;
                    case 3: {
                        float si = opSmoothIntersection(groupDist.x, dj, o.blendRadius);
                        float siID = (groupDist.x > dj) ? groupDist.y : float(j);
                        groupDist = vec2(si, siID);
                    } break;
                    case 4: {
                        float hs = opSubtraction(groupDist.x, dj);
                        float hsID = (-groupDist.x > dj) ? groupDist.y : float(j);
                        groupDist = vec2(hs, hsID);
                    } break;
                    case 5: {
                        float ss = opSmoothSubtraction(groupDist.x, dj, o.blendRadius);
                        float ssID = (groupDist.x < -dj) ? groupDist.y : float(j);
                        groupDist = vec2(ss, ssID);
                    } break;
                }
            }

            sceneDist = minID(groupDist, sceneDist);
            i = last + 1;
        }
    }

    return sceneDist;
}

// ----------------------------------------------------------------------------
// sampleDisplacement:
//    triplanar-blend a height map (R channel) exactly like in triPlanarPBR,
//    but only return the single, blended height value in [0,1].
// ----------------------------------------------------------------------------
float sampleDisplacement(vec3 pos, vec3 N, int heightLayer, float scale) {
    // 1) transform into height‐map space
    vec3 pp = pos * (1.0 / scale);

    // 2) compute the same face weights as triPlanarPBR
    vec3 w = abs(N);
    w = pow(w, vec3(5.0));
    w /= (w.x + w.y + w.z);

    // 3) build UVs for each face, with your flips
    // XY faces (Z axis)
    vec2 uvXY = pp.xy * 0.5 + 0.5;
    if (N.z < 0.0) uvXY.x = 1.0 - uvXY.x;
    uvXY.y = 1.0 - uvXY.y;

    // XZ faces (Y axis)
    vec2 uvXZ = vec2(pp.x, pp.z) * 0.5 + 0.5;
    if (N.y < 0.0) uvXZ.x = 1.0 - uvXZ.x;

    // YZ faces (X axis)
    vec2 uvYZ = vec2(pp.z, pp.y) * 0.5 + 0.5;
    if (N.x < 0.0) uvYZ.x = 1.0 - uvYZ.x;
    uvYZ.y = 1.0 - uvYZ.y;

    // 4) sample the R channel from each slice
    float hXY = texture(textureArray, vec3(uvXY, heightLayer)).r;
    float hXZ = texture(textureArray, vec3(uvXZ, heightLayer)).r;
    float hYZ = texture(textureArray, vec3(uvYZ, heightLayer)).r;

    // 5) blend by the weights
    return hXY * w.z
    + hXZ * w.y
    + hYZ * w.x;
}


vec4 getNormal(vec3 pos) {
    vec2 dist = calcSDF(pos, true);
    vec2 e = vec2(EPSILON, 0.0);

    vec3 normal = dist.x - vec3(
    calcSDF(pos-e.xyy, true).x,
    calcSDF(pos-e.yxy, true).x,
    calcSDF(pos-e.yyx, true).x);

    return vec4(normalize(normal), dist.y);
}

float getObject(Object object, vec3 pos) {
    // 4a) base distance from the raw primitive
    float d = getObjectRaw(object, pos);

    // 4b) if there's a height map, push the surface along the primitive normal
    if (object.heightID >= 0) {
        // numerically computed primitive normal
        vec3 N = getPrimitiveNormal(object, pos);

        // sample [0..1] → center around zero
        float h = sampleDisplacement(pos, N, object.heightID, object.textureScale) - 0.5;

        // push the surface outwards by (h * strength)
        d -= h * DISPLACEMENT_STRENGTH;
    }

    return d;
}

float calcAO(vec3 pos, vec3 normal) { //Ambient occlusion
    float occ = 0.0;
    float sca = 1.0;

    for(int i=0; i<5; i++) {
        float hrconst = 0.03; // larger values = AO
        float hr = hrconst + 0.15*float(i)/4.0;
        vec3 aopos =  normal * hr + pos;
        float dd = calcSDF( aopos , true).x;
        occ += (hr-dd)*sca;
        sca *= 0.95;
    }
    return clamp(1.0 - occ*1.5, 0.0, 1.0);
}

// https://iquilezles.org/articles/rmshadows
float calcSoftshadow(in vec3 ro, in vec3 rd, float mint, float maxt, float w) {
    float res = 1.0;
    float ph = 1e20;
    float t = mint;
    for( int i=0; i<256 && t<maxt; i++ )
    {
        float h = calcSDF(ro + rd*t, false).x;
        if( h<0.001 )
        return 0.0;
        //float y = h*h/(2.0*ph);
        float y = (i==0) ? 0.0 : h*h/(2.0*ph);
        float d = sqrt(h*h-y*y);
        res = min( res, d/(w*max(0.0,t-y)) );
        ph = h;
        t += h;
    }
    return res;
}

float softShadowPCF(vec3 p, vec3 L) {
    const int SAMPLES = 8;
    const float RADIUS = 0.5;    // in world-space
    float sum = 0.0;
    // build two orthonormal tangents
    vec3 T = normalize(cross(abs(L.y) < 0.9 ? vec3(0,1,0) : vec3(1,0,0), L));
    vec3 B = cross(L, T);
    for(int i = 0; i < SAMPLES; i++){
        float theta = 2.0 * 3.14159265 * (float(i) / float(SAMPLES));
        vec3 offsetDir = normalize(L + (T * cos(theta) + B * sin(theta)) * (RADIUS / length(p - u_camPos)));
        sum += calcSoftshadow(p, offsetDir, 0.01, 20.0, 32.0);
    }
    return sum / float(SAMPLES);
}

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

vec3 getMaterial(vec3 p, float id, vec3 normal) {
    Object object = visibleObjects[int(id)];

    if (object.materialID == -1) {
        return vec3(object.r, object.g, object.b);
    }

    if (object.materialID == -2) {
        return triPlanarArray(textureArray, p, normal, object.textureScale, vec3(object.textureXY, object.textureXZ, object.textureYZ));
    }

    if (object.albedoID == -1) {
        return triPlanarArray(textureArray, p, normal, object.textureScale, vec3(object.materialID));
    }

    return triPlanarArray(textureArray, p, normal, object.textureScale, vec3(object.materialID));
}

vec3 getLightPhong(vec3 p, vec3 rd, float id) {
    vec3 lightPos = vec3(200.0, 550.0, -250.0);
    vec3 L = normalize(lightPos - p);
    vec4 N = getNormal(p);
    vec3 V = -rd;
    vec3 R = reflect(-L, N.xyz);

    // Fetch the object's color based on its ID
    int objID = int(id);
    vec3 color = vec3(visibleObjects[objID].r, visibleObjects[objID].g, visibleObjects[objID].b);
    //vec3 color = vec3(objID/100.0f, 0, 0);


    vec3 specColor = vec3(0.6, 0.5, 0.4);
    vec3 specular = 1.3 * specColor * pow(clamp(dot(R, V), 0.0, 1.0), 10.0);
    vec3 diffuse = 0.9 * color * clamp(dot(L, N.xyz), 0.0, 1.0);
    vec3 ambient = 0.05 * color;
    vec3 fresnel = 0.15 * color * pow(1.0 + dot(rd, N.xyz), 3.0);

    // shadows
    float shadow = calcSoftshadow(p, L, 0.01, 100.0, 0.01);
    // occ
    float occ = calcAO(p,N.xyz);
    // back
    vec3 back = 0.05 * color * clamp(dot(N.xyz, -L), 0.0, 1.0);

    return  (back + ambient + fresnel) * occ + (specular * occ + diffuse) * shadow;
}

// PBR lighting calculation
// PBR lighting calculation with improved dark areas
vec3 getLightPBR(vec3 p, vec3 rd, float id) {
    // Setup lighting information
    vec3 lightPos = vec3(200.0, 550.0, -250.0);
    vec3 lightColor = vec3(1.0, 0.95, 0.9);
    float lightIntensity = 20.0;

    // Get the normal at this point
    vec4 normalData = getNormal(p);
    vec3 geomNormal = normalData.xyz;
    int objID = int(normalData.w);

    // Get the object that was hit
    Object obj = visibleObjects[objID];

    // View and light vectors
    vec3 V = normalize(-rd);  // View direction
    vec3 L = normalize(lightPos - p); // Light direction

    // Sample PBR maps using triplanar mapping
    PBRMaps maps = triPlanarPBR(
    textureArray,
    p,
    geomNormal,
    obj.textureScale,
    obj.albedoID,
    obj.normalID,
    obj.metallicID,
    obj.roughnessID,
    obj.aoID,
    obj.heightID,
    V  // view direction for parallax
    );

    // If we don't have albedo texture, use object color
    if (obj.albedoID < 0) {
        maps.albedo = vec3(obj.r, obj.g, obj.b);
    }

    // Transform normal if we have a normal map
    vec3 N = (obj.normalID >= 0) ?
    triPlanarNormal(geomNormal, textureArray, p, obj.textureScale, obj.normalID, V) :
    geomNormal;

    // Shadow calculation
    float shadow = calcSoftshadow(p, L, 0.01, 20.0, 0.8);

    // Calculate Cook-Torrance lighting
    vec3 H = normalize(V + L);
    vec3 radiance = lightColor * lightIntensity * max(dot(N, L), 0.0);

    // Calculate Cook-Torrance BRDF
    vec3 Lo = cookTorrance(N, V, L, maps.albedo, maps.metallic, maps.roughness, maps.ao*calcAO(p, N));
    Lo *= radiance;

    // Calculate geometric AO
    float geometricAO = calcAO(p, N);

    // --- IMPROVEMENTS FOR DARK AREAS ---

    // 1. Improved ambient lighting with hemisphere approach
    vec3 skyColor = vec3(0.5, 0.7, 1.0);
    vec3 groundColor = vec3(0.1, 0.1, 0.1);
    float hemiMix = 0.5 * (N.y + 1.0); // -1 to 1 mapped to 0 to 1
    vec3 hemiLight = mix(groundColor, skyColor, hemiMix);
    vec3 ambient = hemiLight * maps.albedo * maps.ao * geometricAO * 0.2; // Increased from 0.01 to 0.2

    // 2. Add rim lighting (edge highlight effect)
    float rimFactor = 1.0 - max(dot(N, V), 0.0);
    rimFactor = pow(rimFactor, 3.0) * 0.15; // Adjust power and intensity
    vec3 rim = rimFactor * lightColor * maps.albedo;

    // 3. Add bounce light simulation from the ground/nearby surfaces
    vec3 groundBounce = vec3(0.3, 0.2, 0.1) * maps.albedo * max(0.0, -N.y) * 0.1;

    // 4. Add subtle fill light from opposite direction to main light
    vec3 fillLight = maps.albedo * max(0.0, -dot(N, L)) * 0.1;

    // Combine all lighting terms
    vec3 color = ambient + Lo * shadow + rim + groundBounce + fillLight;

    // Energy conservation - make sure we're not adding too much light
    color = min(color, maps.albedo * 2.0);

    return color;
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

vec3 ACESFilmicTone(vec3 x) {
    const float A=2.51, B=0.03, C=2.43, D=0.59, E=0.14;
    return clamp((x*(A*x+B)) / (x*(C*x+D)+E), 0.0, 1.0);
}

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
        color = mix(vec3(1.0), vec3(0.5, 0.7, 1.0), t);
    }

    color = ACESFilmicTone(color);

    // 3) add micro-dither to suppress any residual posterization
    float d = (fract(sin(dot(gl_FragCoord.xy,vec2(12.9898,78.233))) * 43758.5453) - 0.5) / 255.0;
    color += d;

    // Gamma correction
    color = pow(color, vec3(1.0/2.2));

    // Output final color
    FragColor = vec4(color, 1.0);
}

