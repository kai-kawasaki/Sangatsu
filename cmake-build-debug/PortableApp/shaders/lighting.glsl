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
    vec3 lightPos = u_lightPos;
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

// PBR lighting calculation
vec3 getLightPBR(vec3 p, vec3 rd, float id) {
    // Setup lighting information
    vec3 lightPos = u_lightPos;
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
    vec3 ambient = hemiLight * maps.albedo * maps.ao * geometricAO * 0.01; // Increased from 0.01 to 0.2

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