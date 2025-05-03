#include "hg_sdf.glsl"

// Function declarations
float getObjectRaw(Object object, vec3 pos);
float getObject(Object object, vec3 pos);
vec2 calcSDF(vec3 pos, bool cull);
vec3 getPrimitiveNormal(Object object, vec3 pos);
float sampleDisplacement(vec3 pos, vec3 N, int heightLayer, float scale);
vec4 getNormal(vec3 pos);
// ----------------------------------------------------------------------------

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
        d -= h * object.displacementStrength;
    }

    return d;
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

vec4 getNormal(vec3 pos) {
    vec2 dist = calcSDF(pos, true);
    vec2 e = vec2(EPSILON, 0.0);

    vec3 normal = dist.x - vec3(
    calcSDF(pos-e.xyy, true).x,
    calcSDF(pos-e.yxy, true).x,
    calcSDF(pos-e.yyx, true).x);

    return vec4(normalize(normal), dist.y);
}