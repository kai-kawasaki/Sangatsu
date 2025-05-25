struct Object {
    float x, y, z;        // position
    float r, g, b;        // color
    float i, j, k;        // scale
    int objectType;
    int operation;
    float blendRadius;
    int groupLength;
    int materialID;
    float textureScale;
    // PBR texture layers
    int albedoID;
    int normalID;
    int metallicID;
    int roughnessID;
    int aoID;
    int heightID;
    float displacementStrength;
};

layout (std430, binding = 0) buffer AllObjects {
    Object allObjects[];
};

struct BVHNode {
    vec4 boundsMin;   // xyz = min,   w = unused
    vec4 boundsMax;   // xyz = max,   w = unused
    ivec4 child;      // x = left, y = right, z = start, w = count
};

layout (std430, binding = 1) buffer BVHNodes {
    BVHNode nodes[];
};

layout (std430, binding = 2) buffer BVHIndices {
    int objectIndices[];
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
uniform vec3 u_lightPos;

uniform sampler2DArray textureArray;

// Constants
const float MAX_STEPS = 500.0;
const float MIN_DIST_TO_SDF = 0.001;
const float MAX_DIST_TO_TRAVEL = 100.0;
const float EPSILON = 0.0001;
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

vec2 minID(vec2 res1, vec2 res2) {
    return (res1.x < res2.x) ? res1 : res2;
}

// helper for intersection: pick the farthest distance, tracking ID
vec2 maxID(vec2 a, vec2 b) {
    return (a.x > b.x) ? a : b;
}

// Unpack normal map to [-1,1] range
vec3 unpackNormal(vec3 rgb) {
    return normalize(rgb * 2.0 - 1.0);
}

struct HitInfo {
    float distance;
    int objectID;
};

layout (local_size_x = 8, local_size_y = 8) in;
layout (binding = 0, rgba32f) uniform writeonly image2D resultImage;

layout (binding = 1, rgba16f) uniform image2D reflectionCache;
layout (binding = 2, rgba16f) uniform image2D shadowCache;

#define DEFAULTROUGHNESS 0.9
#define DEFAULTMETALLIC 0.1