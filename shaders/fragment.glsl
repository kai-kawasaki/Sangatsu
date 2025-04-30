#version 430 core
#include "hg_sdf.glsl"

in vec3 color;
layout (location = 0) out vec4 FragColor;

struct Object {
    float x, y, z; // position
    float r, g, b; // color
    float i, j, k; // scale
    int objectType;
    int operation;
    float blendRadius;
    int groupLength;
    int materialID;
    int textureXY;
    int textureXZ;
    int textureYZ;
    float textureScale;
// New PBR texture layers
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

const float MAX_STEPS = 500.0;
const float MIN_DIST_TO_SDF = 0.001;
const float MAX_DIST_TO_TRAVEL = 100.0;
const float EPSILON = 0.001;
const float LOD_MULTIPLIER = 0.06;
//const float PI = 3.14159265359;


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

    // 2) Compute blend weights
    vec3 w = abs(n);
    w = pow(w, vec3(5.0));
    w /= (w.x + w.y + w.z);

    // 3) UVs per plane
    // --- XY plane (+Z/–Z faces) ---
    vec2 uvXY = pp.xy * 0.5 + 0.5;
    if (n.z < 0.0) {
        uvXY.x = 1.0 - uvXY.x;
    }
    uvXY.y = 1.0 - uvXY.y;

    // --- XZ plane (+Y/–Y faces) ---
    vec2 uvXZ = vec2(pp.x, pp.z) * 0.5 + 0.5;
    if (n.y > 0.0) {
        uvXZ.x = 1.0 - uvXZ.x;
    }

    // --- YZ plane (+X/–X faces) ---
    vec2 uvYZ = vec2(pp.z, pp.y) * 0.5 + 0.5;
    if (n.x > 0.0) {
        uvYZ.x = 1.0 - uvYZ.x;
    }
    uvYZ.y = 1.0 - uvYZ.y;

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

    vec3 w = abs(geomNormal);
    w = pow(w, vec3(5.0));
    w /= (w.x + w.y + w.z);

    // Create tangent frames for each plane
    vec3 tangentXY, bitangentXY;
    vec3 tangentXZ, bitangentXZ;
    vec3 tangentYZ, bitangentYZ;

    // XY plane (Z normal)
    if (abs(geomNormal.z) > 0.0) {
        tangentXY = normalize(vec3(1.0, 0.0, 0.0));
        bitangentXY = normalize(vec3(0.0, 1.0, 0.0));
    } else {
        tangentXY = normalize(vec3(1.0, 0.0, 0.0));
        bitangentXY = normalize(cross(geomNormal, tangentXY));
    }

    // XZ plane (Y normal)
    if (abs(geomNormal.y) > 0.0) {
        tangentXZ = normalize(vec3(1.0, 0.0, 0.0));
        bitangentXZ = normalize(vec3(0.0, 0.0, 1.0));
    } else {
        tangentXZ = normalize(vec3(1.0, 0.0, 0.0));
        bitangentXZ = normalize(cross(geomNormal, tangentXZ));
    }

    // YZ plane (X normal)
    if (abs(geomNormal.x) > 0.0) {
        tangentYZ = normalize(vec3(0.0, 1.0, 0.0));
        bitangentYZ = normalize(vec3(0.0, 0.0, 1.0));
    } else {
        tangentYZ = normalize(vec3(0.0, 1.0, 0.0));
        bitangentYZ = normalize(cross(geomNormal, tangentYZ));
    }

    // Sample normal map for each face
    vec3 pp = p * (1.0/scale);

    // --- XY plane (+Z/–Z faces) ---
    vec2 uvXY = pp.xy * 0.5 + 0.5;
    if (geomNormal.z < 0.0) {
        uvXY.x = 1.0 - uvXY.x;
    }
    uvXY.y = 1.0 - uvXY.y;

    // --- XZ plane (+Y/–Y faces) ---
    vec2 uvXZ = vec2(pp.x, pp.z) * 0.5 + 0.5;
    if (geomNormal.y > 0.0) {
        uvXZ.x = 1.0 - uvXZ.x;
    }

    // --- YZ plane (+X/–X faces) ---
    vec2 uvYZ = vec2(pp.z, pp.y) * 0.5 + 0.5;
    if (geomNormal.x > 0.0) {
        uvYZ.x = 1.0 - uvYZ.x;
    }
    uvYZ.y = 1.0 - uvYZ.y;

    // Sample and unpack normals
    vec3 nXY = unpackNormal(texture(arr, vec3(uvXY, normalLayer)).rgb);
    vec3 nXZ = unpackNormal(texture(arr, vec3(uvXZ, normalLayer)).rgb);
    vec3 nYZ = unpackNormal(texture(arr, vec3(uvYZ, normalLayer)).rgb);

    // Transform from tangent to world space for each plane
    vec3 worldXY = nXY.x * tangentXY + nXY.y * bitangentXY + nXY.z * vec3(0.0, 0.0, 1.0);
    vec3 worldXZ = nXZ.x * tangentXZ + nXZ.y * bitangentXZ + nXZ.z * vec3(0.0, 1.0, 0.0);
    vec3 worldYZ = nYZ.x * tangentYZ + nYZ.y * bitangentYZ + nYZ.z * vec3(1.0, 0.0, 0.0);

    // Blend normals based on original weights
    return normalize(worldXY * w.z + worldXZ * w.y + worldYZ * w.x);
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

float getObject(Object object, vec3 pos) {
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

vec4 getNormal(vec3 pos) {
    vec2 dist = calcSDF(pos, true);
    vec2 e = vec2(EPSILON, 0.0);

    vec3 normal = dist.x - vec3(
    calcSDF(pos-e.xyy, true).x,
    calcSDF(pos-e.yxy, true).x,
    calcSDF(pos-e.yyx, true).x);

    return vec4(normalize(normal), dist.y);
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
vec3 getLightPBR(vec3 p, vec3 rd, float id) {
    // Setup lighting information
    vec3 lightPos = vec3(200.0, 550.0, -250.0);
    vec3 lightColor = vec3(1.0, 0.95, 0.9);
    float lightIntensity = 200.0;

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
    float shadow = calcSoftshadow(p, L, 0.01, 20.0, 16.0);

    // Calculate Cook-Torrance lighting
    vec3 H = normalize(V + L);
    vec3 radiance = lightColor * lightIntensity * max(dot(N, L), 0.0);

    // Calculate Cook-Torrance BRDF
    vec3 Lo = cookTorrance(N, V, L, maps.albedo, maps.metallic, maps.roughness, maps.ao*calcAO(p, N));
    Lo *= radiance;

    // Ambient lighting
    vec3 ambient = vec3(0.03) * maps.albedo * maps.ao * calcAO(p, N);

    // Final color
    vec3 color = ambient + Lo * shadow;

    // Apply tone mapping (optional)
    color = color / (color + vec3(1.0));

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

    // Gamma correction
    color = pow(color, vec3(1.0/2.2));

    // Output final color
    FragColor = vec4(color, 1.0);
}

