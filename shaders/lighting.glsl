
#define REFLECTIONS true
#define RAYBOUNCES 2
#define REFLECTIONSTRENGTH 0.2
#define REFLECTIONFALLOFF 0.5


float getShadow (vec3 pos, vec3 normal, vec3 lightDir, float roughness) {
    // Use the original normal for shadow calculation
    float shadowBias = 0.02;
    float dist = traceBVH(pos + normal * shadowBias, lightDir).distance;
    return dist < MAX_DIST_TO_TRAVEL ? 0.0 : 1.0;
}

//float getShadow(vec3 pos, vec3 normal, vec3 lightDir, float roughness) {
//    // Get pixel coordinates from GlobalInvocationID
//    ivec2 pixelCoord = ivec2(gl_GlobalInvocationID.xy);
//
//    // Determine sampling rate based on roughness
//    // Rougher surfaces can use coarser shadow sampling
//    int downsampleFactor;
//    if(roughness > 0.7) {
//        downsampleFactor = 4; // Very coarse for rough surfaces
//    } else if(roughness > 0.4) {
//        downsampleFactor = 2; // Medium for semi-rough surfaces
//    } else {
//        downsampleFactor = 1; // Finer detail for smooth surfaces
//    }
//
//    // Create a pattern based on pixel coordinates
//    bool shouldTrace = (pixelCoord.x % downsampleFactor == 0) &&
//    (pixelCoord.y % downsampleFactor == 0);
//
//    // For pixels that don't trace, fetch from cache
//    if(!shouldTrace) {
//        // Find nearest cache pixel
//        ivec2 cacheCoord = (pixelCoord / downsampleFactor) * downsampleFactor;
//        return imageLoad(shadowCache, cacheCoord).r;
//    }
//
//    // For pixels that do trace, calculate shadow normally
//    float shadowBias = 0.02;
//    float dist = traceBVH(pos + normal * shadowBias, lightDir).distance;
//    float shadow = 1.0;
//
//    if(dist < MAX_DIST_TO_TRAVEL) {
//        shadow = 0.0; // In shadow
//    }
//
//    // Store the result in the cache
//    imageStore(shadowCache, pixelCoord, vec4(shadow, 0.0, 0.0, 0.0));
//
//    return shadow;
//}


// Add a helper function to reflect a ray around a normal
void reflectRay(inout vec3 rayD, in vec3 normal) {
    rayD = rayD + 2.0 * -dot(normal, rayD) * normal;
}

// Fast stylized PBR shading with improved triplanar mapping
vec3 fastPBR(vec3 pos, vec3 rd, vec3 normal, int objID) {
    Object obj = allObjects[objID];

    // Get object properties
    vec3 baseColor = vec3(obj.r, obj.g, obj.b);
    float baseRoughness = 0.8;
    float baseMetallic = 0.2;

    // Improved triplanar mapping with better blending
    vec3 absN = abs(normal);

    // Detect edges for adaptive blending power
    float edgeFactor = max(max(absN.x, absN.y), absN.z) - min(min(absN.x, absN.y), absN.z);
    float blendPower = mix(3.0, 5.0, edgeFactor);

    // Calculate blend weights
    vec3 weights = pow(absN, vec3(blendPower));
    weights /= (weights.x + weights.y + weights.z);

    // Get texture coordinates for each axis
    vec3 pp = pos * obj.textureScale;
    vec2 uvX = fract(pp.yz * 0.5 + 0.5); // X-axis
    vec2 uvY = fract(pp.xz * 0.5 + 0.5); // Y-axis
    vec2 uvZ = fract(pp.xy * 0.5 + 0.5); // Z-axis

    // Material properties
    vec3 albedo = baseColor;
    float roughness = baseRoughness;
    float metallic = baseMetallic;
    float ao = 1.0;

    // Sample textures if available
    if (obj.albedoID >= 0) {
        vec3 texX = texture(textureArray, vec3(uvX, obj.albedoID)).rgb;
        vec3 texY = texture(textureArray, vec3(uvY, obj.albedoID)).rgb;
        vec3 texZ = texture(textureArray, vec3(uvZ, obj.albedoID)).rgb;
        albedo = texX * weights.x + texY * weights.y + texZ * weights.z;
    }

    if (obj.roughnessID >= 0) {
        float rX = texture(textureArray, vec3(uvX, obj.roughnessID)).r;
        float rY = texture(textureArray, vec3(uvY, obj.roughnessID)).r;
        float rZ = texture(textureArray, vec3(uvZ, obj.roughnessID)).r;
        roughness = rX * weights.x + rY * weights.y + rZ * weights.z;
    }

    if (obj.metallicID >= 0) {
        float mX = texture(textureArray, vec3(uvX, obj.metallicID)).r;
        float mY = texture(textureArray, vec3(uvY, obj.metallicID)).r;
        float mZ = texture(textureArray, vec3(uvZ, obj.metallicID)).r;
        metallic = mX * weights.x + mY * weights.y + mZ * weights.z;
    }

    if (obj.aoID >= 0) {
        float aoX = texture(textureArray, vec3(uvX, obj.aoID)).r;
        float aoY = texture(textureArray, vec3(uvY, obj.aoID)).r;
        float aoZ = texture(textureArray, vec3(uvZ, obj.aoID)).r;
        ao = aoX * weights.x + aoY * weights.y + aoZ * weights.z;
    }

    // Save original normal for shadow calculation
    vec3 shadowTestNormal = normal;

    // Apply normal mapping if available
    if (obj.normalID >= 0) {
        // For normal mapping, we need tangent space
        vec3 upVector = abs(normal.y) > 0.99 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
        vec3 tangent = normalize(cross(normal, upVector));
        vec3 bitangent = normalize(cross(normal, tangent));
        mat3 TBN = mat3(tangent, bitangent, normal);

        // Get normal maps for each plane
        vec3 nmX = texture(textureArray, vec3(uvX, obj.normalID)).rgb * 2.0 - 1.0;
        vec3 nmY = texture(textureArray, vec3(uvY, obj.normalID)).rgb * 2.0 - 1.0;
        vec3 nmZ = texture(textureArray, vec3(uvZ, obj.normalID)).rgb * 2.0 - 1.0;

        // Blend normal maps and transform to world space
        vec3 blendedNormalMap = normalize(
        nmX * weights.x +
        nmY * weights.y +
        nmZ * weights.z
        );

        normal = normalize(TBN * blendedNormalMap);
    }

    // Lighting calculation
    vec3 lightDir = normalize(u_lightPos - pos);
    float NdotL = max(dot(normal, lightDir), 0.0);

    NdotL *= getShadow(pos, normal, lightDir, roughness); // Apply shadow

    // PBR lighting
    vec3 F0 = mix(vec3(0.04), albedo, metallic);
    vec3 diffuse = albedo * (1.0 - metallic) * NdotL;

    // Specular reflection
    vec3 viewDir = -rd;
    vec3 halfDir = normalize(lightDir + viewDir);
    float NdotH = max(dot(normal, halfDir), 0.0);

    // Specular power based on roughness
    float specPower = 2.0 / (roughness * roughness + 0.01) - 2.0;
    vec3 specular = F0 * pow(NdotH, specPower) * NdotL;

    // Apply ambient occlusion
    diffuse *= ao;
    specular *= ao;

    // Ambient lighting with environment influence
    vec3 ambient = albedo * 0.1 * ao;

    // Combine lighting components
    return ambient + diffuse + specular;
}

// Simple stylized reflection
//vec3 getReflection(vec3 pos, vec3 rd, vec3 normal, float metallic, float roughness) {
//    if(metallic < 0.1) return vec3(0.0);
//
//    vec3 reflDir = reflect(rd, normal);
//
//    // Add roughness perturbation
//    if(roughness > 0.01) {
//        vec3 noise = fract(sin(pos * 12.345) * 43758.5453) - 0.5;
//        reflDir = normalize(reflDir + noise * roughness * 0.3);
//    }
//
//    HitInfo hit = traceBVH(pos + normal * 0.01, reflDir);
//    float reflDist = hit.distance;
//
//    if(reflDist < MAX_DIST_TO_TRAVEL) {
//        vec3 reflPos = pos + normal * 0.01 + reflDir * reflDist;
//        vec4 reflNormalData = getNormal(reflPos);
//        vec3 reflNormal = reflNormalData.xyz;
//        int reflObjID = int(reflNormalData.w);
//        //        vec3 reflNormal = getPrimitiveNormal(allObjects[hit.objectID], reflPos);
//        //        int reflObjID = hit.objectID;
//
//        return fastPBR(reflPos, reflDir, reflNormal, reflObjID);
//    }
//
//    // Sky color for missed reflections
//    return vec3(0.6, 0.7, 0.9);
//}

// Stylized reflection with caching and downsampling
vec3 getReflection(vec3 pos, vec3 rd, vec3 normal, float metallic, float roughness) {
    if(metallic < 0.1) return vec3(0.0);

    // Get pixel coordinates from GlobalInvocationID
    ivec2 pixelCoord = ivec2(gl_GlobalInvocationID.xy);
    ivec2 cacheSize = imageSize(reflectionCache);

    // Determine sampling rate based on roughness
    int downsampleFactor;
    if(roughness > 0.7) {
        downsampleFactor = 4; // 1/16 of the pixels
    } else if(roughness > 0.4) {
        downsampleFactor = 2; // 1/4 of the pixels
    } else {
        downsampleFactor = 1; // All pixels for smooth surfaces
    }

    // Create a pattern based on pixel coordinates
    bool shouldTrace = (pixelCoord.x % downsampleFactor == 0) &&
    (pixelCoord.y % downsampleFactor == 0);

    // For pixels that don't trace, fetch from cache
    if(!shouldTrace) {
        // Find nearest cache pixel
        ivec2 cacheCoord = (pixelCoord / downsampleFactor) * downsampleFactor;
        return imageLoad(reflectionCache, cacheCoord).rgb;
    }


    // For pixels that do trace, calculate reflection normally
    vec3 reflDir = reflect(rd, normal);

    // Add roughness perturbation
    if(roughness > 0.01) {
        vec3 noise = fract(sin(pos * 12.345) * 43758.5453) - 0.5;
        reflDir = normalize(reflDir + noise * roughness * 0.3);
    }

    HitInfo hit = traceBVH(pos + normal * 0.01, reflDir);
    float reflDist = hit.distance;

    vec3 reflColor;
    if(reflDist < MAX_DIST_TO_TRAVEL) {
        vec3 reflPos = pos + normal * 0.01 + reflDir * reflDist;
        vec4 reflNormalData = getNormal(reflPos);
        vec3 reflNormal = reflNormalData.xyz;
        int reflObjID = int(reflNormalData.w);

        reflColor = fastPBR(reflPos, reflDir, reflNormal, reflObjID);
    } else {
        // Sky color for missed reflections
        reflColor = vec3(0.6, 0.7, 0.9);
    }

    // Store the result in the cache
    imageStore(reflectionCache, pixelCoord, vec4(reflColor, 1.0));

    return reflColor;
}