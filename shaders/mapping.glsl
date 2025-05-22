
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