//float calcAO(vec3 pos, vec3 normal) { //Ambient occlusion
//                                      float occ = 0.0;
//                                      float sca = 1.0;
//
//                                      for(int i=0; i<5; i++) {
//                                          float hrconst = 0.03; // larger values = AO
//                                          float hr = hrconst + 0.15*float(i)/4.0;
//                                          vec3 aopos =  normal * hr + pos;
//                                          float dd = calcSDF( aopos ).x;
//                                          occ += (hr-dd)*sca;
//                                          sca *= 0.95;
//                                      }
//                                      return clamp(1.0 - occ*1.5, 0.0, 1.0);
//}

#define REFLECTIONS true
#define RAYBOUNCES 2
#define REFLECTIONSTRENGTH 0.2
#define REFLECTIONFALLOFF 0.5

// Add a helper function to reflect a ray around a normal
void reflectRay(inout vec3 rayD, in vec3 normal) {
    rayD = rayD + 2.0 * -dot(normal, rayD) * normal;
}


// 1) Precompute your “height” offsets once at compile time:
const int   AO_SAMPLES = 6;
const float AO_OFFSETS[AO_SAMPLES] = float[](0.02, 0.05, 0.09, 0.14, 0.20, 0.27);
const float AO_FALLOFF   = 0.95;
const float AO_SCALE     = 1.5;

float calcAO(vec3 pos, vec3 normal) {
    float occ = 0.0;
    float sca = 1.0;

    // 2) Fewer, well-spaced samples:
    for (int i = 0; i < AO_SAMPLES; ++i) {
        float hr = AO_OFFSETS[i];
        float dd = calcSDF(pos + normal * hr).x;
        occ += (hr - dd) * sca;

        // 3) Early-exit if we’ve already occluded fully:
        if (occ * AO_SCALE >= 1.0) {
            return 0.0;
        }
        sca *= AO_FALLOFF;
    }

    return 1.0 - clamp(occ * AO_SCALE, 0.0, 1.0);
}

const int   SHADOW_SAMPLES = 64;
const float MIN_HIT        = 0.0001;
const float RES_THRESHOLD  = 0.001;  // once res is this low, treat as full shadow

float calcSoftshadow(in vec3 ro, in vec3 rd, float mint, float maxt, float w) {
    float res = 1.0;
    float ph  = 1e20;
    float t   = mint;

    for (int i = 0; i < SHADOW_SAMPLES && t < maxt; ++i) {
        float h = calcSDF(ro + rd * t).x;
        if (h < MIN_HIT)
        return 0.0;

        float y = (i == 0) ? 0.0 : (h*h)/(2.0*ph);
        float d = sqrt(max(0.0, h*h - y*y));
        res = min(res, d/(w * max(0.0, t - y)));
        if (res < RES_THRESHOLD)
        return 0.0;    // early‐exit full shadow

        ph = h;
        t += h;
    }
    return res;
}

float hardShadowTest(in vec3 ro, in vec3 rd, float nearT, float farT) {
    // No ray bias at all - let the BVH and sphere tracer handle it
    float hit = traceBVH(ro, rd);

    // Use a more forgiving threshold to catch thin structures
    return (hit > farT || hit < nearT) ? 1.0 : 0.0;
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

vec3 getMaterial(vec3 p, float id, vec3 normal) {
    Object object = allObjects[int(id)];

    if (object.materialID == -1) {
        return vec3(object.r, object.g, object.b);
    }

//    if (object.materialID == -2) {
//        return triPlanarArray(textureArray, p, normal, object.textureScale, vec3(object.textureXY, object.textureXZ, object.textureYZ));
//    }

    if (object.albedoID == -1) {
        return triPlanarArray(textureArray, p, normal, object.textureScale, vec3(object.materialID));
    }

    return triPlanarArray(textureArray, p, normal, object.textureScale, vec3(object.materialID));
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

float improvedHardShadowTest(in vec3 ro, in vec3 rd, vec3 N, float nearT, float farT) {
    // Calculate view distance (only once)
    float viewDistance = length(ro - u_camPos);

    // Factor in the light angle with a single dot product
    float NdotL = max(dot(N, rd), 0.0);

    // Combine distance and angle factors without expensive operations
    float bias = MIN_DIST_TO_SDF * (1.0 + viewDistance * 0.01) * (1.0 + (1.0 - NdotL) * 2.0);

    // Apply the bias directly
    vec3 biasedOrigin = ro + rd * bias;

    // Single BVH trace
    float hit = traceBVH(biasedOrigin, rd);

    return hit > farT || hit < nearT ? 1.0 : 0.05;
}


// In lighting.glsl
vec3 getLightPBR(vec3 p, vec3 rd, float id, PBRMaps maps) {
    // Setup lighting information
    vec3 lightPos = u_lightPos;
    vec3 lightColor = vec3(1.0, 0.95, 0.9);
    float lightIntensity = 20.0;

    // Get the normal at this point
    vec4 normalData = getNormal(p);
    vec3 geomNormal = normalData.xyz;
    int objID = int(normalData.w);

    // Get the object that was hit
    Object obj = allObjects[objID];

    // View and light vectors
    vec3 V = normalize(-rd);  // View direction
    vec3 L = normalize(lightPos - p); // Light direction

    // Apply displacement mapping using height map
    vec3 displacePos = p;
    if (obj.heightID >= 0 && obj.displacementStrength > 0.0) {
        // Sample height map using triplanar mapping
        float height = triPlanarArray(
        textureArray,
        p,
        geomNormal,
        obj.textureScale,
        vec3(obj.heightID)
        ).r;

        // Displace position along the normal
        displacePos = p + geomNormal * height * obj.displacementStrength;

        // Update the normal after displacement
        vec4 newNormalData = getNormal(displacePos);
        geomNormal = newNormalData.xyz;
    }

    // If we don't have albedo texture, use object color
    if (obj.albedoID < 0) {
        maps.albedo = vec3(obj.r, obj.g, obj.b);
    }

    // Transform normal if we have a normal map
    vec3 N = (obj.normalID >= 0) ?
    triPlanarNormal(geomNormal, textureArray, displacePos, obj.textureScale, obj.normalID, V) :
    geomNormal;

    // Shadow calculation
    float shadow = improvedHardShadowTest(displacePos, L, N, EPSILON, 20.0);

    // Calculate geometric AO
    float geometricAO = calcAO(displacePos, N);

    // Calculate Cook-Torrance lighting
    vec3 H = normalize(V + L);
    vec3 radiance = lightColor * lightIntensity * max(dot(N, L), 0.0);

    // Adjust metallic and roughness for more realistic metals
    // For metals (high metallic value), increase minimum roughness
    float adjustedRoughness = maps.roughness;
    if (maps.metallic > 0.7) {
        // Set minimum roughness for metals to prevent mirror-like reflections
        adjustedRoughness = max(adjustedRoughness, 0.1);
    }

    // Calculate Cook-Torrance BRDF with adjusted roughness
    vec3 Lo = cookTorrance(N, V, L, maps.albedo, maps.metallic, adjustedRoughness, maps.ao*geometricAO);
    Lo *= radiance;

    // --- IMPROVEMENTS FOR DARK AREAS ---

    // 1. Improved ambient lighting with hemisphere approach
    vec3 skyColor = vec3(0.5, 0.7, 1.0);
    vec3 groundColor = vec3(0.1, 0.1, 0.1);
    float hemiMix = 0.5 * (N.y + 1.0); // -1 to 1 mapped to 0 to 1
    vec3 hemiLight = mix(groundColor, skyColor, hemiMix);
    vec3 ambient = hemiLight * maps.albedo * maps.ao * geometricAO * 0.02; // Increased slightly

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

    // --- REFLECTIONS ---
    if (REFLECTIONS && maps.metallic > 0.1) {
        // Calculate reflection ray
        vec3 reflectedRay = reflect(rd, N);

        // Add roughness-based variation to reflection direction
        if (adjustedRoughness > 0.0) {
            // Create roughness-based noise vector
            vec3 noiseOffset = vec3(
            fract(sin(dot(displacePos.yz, vec2(12.9898, 78.233))) * 43758.5453),
            fract(sin(dot(displacePos.xz, vec2(12.9898, 78.233))) * 43758.5453),
            fract(sin(dot(displacePos.xy, vec2(12.9898, 78.233))) * 43758.5453)
            ) - 0.5;

            // Apply roughness-scaled noise to reflection direction
            float roughnessScale = adjustedRoughness * 0.5;
            reflectedRay = normalize(reflectedRay + noiseOffset * roughnessScale);
        }

        // Cast reflection ray
        vec3 reflectOrigin = displacePos + N * 0.01; // Offset along normal to avoid self-intersection
        float reflectDist = traceBVH(reflectOrigin, reflectedRay);

        vec3 reflectedColor = vec3(0.0);
        if (reflectDist < MAX_DIST_TO_TRAVEL) {
            vec3 reflectPos = reflectOrigin + reflectedRay * reflectDist;
            reflectedColor = getMaterial(reflectPos, reflectDist, reflectedRay).xyz;
        } else {
            // Simple skybox for reflections
            vec3 skyDir = normalize(reflectedRay);
            float skyGradient = 0.5 + 0.5 * skyDir.y;
            reflectedColor = mix(vec3(0.6, 0.7, 0.9), vec3(0.4, 0.5, 1.0), skyGradient);

            // Add a sun highlight in reflections
            float sunDot = max(dot(skyDir, normalize(u_lightPos)), 0.0);
            float sunHighlight = pow(sunDot, 64.0);
            reflectedColor += vec3(1.0, 0.9, 0.7) * sunHighlight * 2.0;
        }

        // Metals tint their reflections with their base color
        if (maps.metallic > 0.7) {
            // Mix reflection color with base color for metallic surfaces
            reflectedColor = mix(reflectedColor, reflectedColor * maps.albedo, maps.metallic * 0.7);
        }

        // Calculate fresnel factor for view-dependent reflections
        float fresnelFactor = pow(1.0 - max(dot(N, V), 0.0), 3.0);

        // Calculate reflection strength based on metallic and roughness
        float reflectionStrength = mix(
        maps.metallic * 0.6,
        maps.metallic * 0.8,
        fresnelFactor
        ) * (1.0 - adjustedRoughness * 0.5) * REFLECTIONSTRENGTH;

        // Apply reflections
        color = mix(color, reflectedColor, reflectionStrength);
    }

    // Energy conservation - make sure we're not adding too much light
    color = min(color, maps.albedo * 2.0);

    return color;
}