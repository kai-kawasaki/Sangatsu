#include "hg_sdf.glsl"

// Function declarations
float getObjectRaw(Object object, vec3 pos);
float getObject(Object object, vec3 pos);
//vec2 calcSDF(vec3 pos);
float calcSDF(vec3 pos, int start, int count);
vec3 getPrimitiveNormal(Object object, vec3 pos);
vec3 analyticNormal(Object object, vec3 p);
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
        case 11:
            return fMandelbulb(pos-location, object.i);
    }
    return 0.0;
}

float getObject(Object object, vec3 pos) {
    // 4a) base distance from the raw primitive
    float d = getObjectRaw(object, pos);

    // 4b) if there's a height map, push the surface along the primitive normal
    if (object.heightID >= 0) {
        // numerically computed primitive normal
//        vec3 N = analyticNormal(object, pos);
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
    vec3 pp = pos * scale;

    // 2) compute the same face weights as triPlanarPBR
    vec3 w = abs(N);
    w = pow(w, vec3(5.0));
    w /= (w.x + w.y + w.z);

    // 3) compute the UV coordinates for each face
    vec2 uvXY = fract(pp.xy * 0.5 + 0.5);
    vec2 uvXZ = fract(vec2(pp.x, pp.z) * 0.5 + 0.5);
    vec2 uvYZ = fract(vec2(pp.z, pp.y) * 0.5 + 0.5);

    // face flips for Minecraft-style UVs
/*
    if (N.z < 0.0) uvXY.x = 1.0 - uvXY.x;
    uvXY.y = 1.0 - uvXY.y;
    if (N.y < 0.0) uvXZ.x = 1.0 - uvXZ.x;
    if (N.x < 0.0) uvYZ.x = 1.0 - uvYZ.x;
    uvYZ.y = 1.0 - uvYZ.y;
*/

    // 4) sample the R channel from each slice
    float hXY = texture(textureArray, vec3(uvXY, heightLayer)).r;
    float hXZ = texture(textureArray, vec3(uvXZ, heightLayer)).r;
    float hYZ = texture(textureArray, vec3(uvYZ, heightLayer)).r;

    // 5) blend by the weights
    return hXY * w.z
    + hXZ * w.y
    + hYZ * w.x;
}

float calcSDF(vec3 pos, int start, int count) {
    float minDist = MAX_DIST_TO_TRAVEL;

    for (int i = 0; i < count; ++i) {
        int oid = objectIndices[start + i];
        Object o = allObjects[oid];
        float d = getObject(o, pos);
        minDist = min(minDist, d);
    }

    return minDist;
}

//vec2 calcSDF(vec3 pos) {
//    vec2 sceneDist = vec2(MAX_DIST_TO_TRAVEL, -1.0);
//
//    int i = 0;
//    while (i < allObjects.length()) {
//        Object head = allObjects[i];
//        int last = min(i + head.groupLength, allObjects.length() - 1);
//
//        float d0 = getObject(head, pos);
//        vec2 groupDist = vec2(d0, float(i));
//
//        for (int j = i + 1; j <= last; ++j) {
//            Object o = allObjects[j];
//            float dj = getObject(o, pos);
//
//            switch (o.operation) {
//                case 0: {
//                            float u = opUnion(groupDist.x, dj);
//                            float uID = (groupDist.x < dj) ? groupDist.y : float(j);
//                            groupDist = vec2(u, uID);
//                        } break;
//                case 1: {
//                            float su = opSmoothUnion(groupDist.x, dj, o.blendRadius);
//                            float suID = (groupDist.x < dj) ? groupDist.y : float(j);
//                            groupDist = vec2(su, suID);
//                        } break;
//                case 2: {
//                            groupDist = maxID(vec2(dj, float(j)), groupDist);
//                        } break;
//                case 3: {
//                            float si = opSmoothIntersection(groupDist.x, dj, o.blendRadius);
//                            float siID = (groupDist.x > dj) ? groupDist.y : float(j);
//                            groupDist = vec2(si, siID);
//                        } break;
//                case 4: {
//                            float hs = opSubtraction(groupDist.x, dj);
//                            float hsID = (-groupDist.x > dj) ? groupDist.y : float(j);
//                            groupDist = vec2(hs, hsID);
//                        } break;
//                case 5: {
//                            float ss = opSmoothSubtraction(groupDist.x, dj, o.blendRadius);
//                            float ssID = (groupDist.x < -dj) ? groupDist.y : float(j);
//                            groupDist = vec2(ss, ssID);
//                        } break;
//            }
//        }
//
//        sceneDist = minID(groupDist, sceneDist);
//        i = last + 1;
//    }
//
//    return sceneDist;
//}

// fast AABB‐SDF for culling
//float sdBox(vec3 p, vec3 b) {
//    vec3 d = abs(p) - b;
//    vec3 m = max(d, vec3(0.0));
//    return length(m) + min(max(d.x, max(d.y, d.z)), 0.0);
//}
//
//vec2 calcSDF(vec3 pos) {
//    vec2 sceneDist = vec2(MAX_DIST_TO_TRAVEL, -1.0);
//
//    // Simple fixed‐size stack
//    int stack[32];
//    int top = 0;
//    stack[top++] = 0; // root node
//
//    while (top > 0) {
//        int idx = stack[--top];
//        BVHNode n = nodes[idx];
//
//        // reconstruct box center & extent
//        vec3 bMin = n.boundsMin.xyz;
//        vec3 bMax = n.boundsMax.xyz;
//        vec3 center = (bMin + bMax) * 0.5;
//        vec3 extent = (bMax - bMin) * 0.5;
//
//        // fast AABB‐SDF
//        float dBox = sdBox(pos - center, extent);
//        if (dBox > sceneDist.x) continue;      // prune whole subtree
//
//        // leaf?
//        if (n.child.x < 0) {
//            int start = n.child.z;
//            int count = n.child.w;
//            for (int i = 0; i < count; ++i) {
//                int oid = objectIndices[start + i];
//                Object o = allObjects[oid];
//                float d = getObject(o, pos);
//                sceneDist = minID(vec2(d, float(oid)), sceneDist);
//            }
//        } else {
//            // internal: sort children by their box‐distance
//            int left  = n.child.x;
//            int right = n.child.y;
//
//            // load children
//            BVHNode ln = nodes[left];
//            BVHNode rn = nodes[right];
//            // compute their box‐SDFs
//            vec3  lCenter = (ln.boundsMin.xyz + ln.boundsMax.xyz)*0.5;
//            vec3  lExtent = (ln.boundsMax.xyz - ln.boundsMin.xyz)*0.5;
//            float dL = sdBox(pos - lCenter, lExtent);
//
//            vec3  rCenter = (rn.boundsMin.xyz + rn.boundsMax.xyz)*0.5;
//            vec3  rExtent = (rn.boundsMax.xyz - rn.boundsMin.xyz)*0.5;
//            float dR = sdBox(pos - rCenter, rExtent);
//
//            // push *farther* first so the *nearer* is popped next
//            if (dL < dR) {
//                if (dR <= sceneDist.x) stack[top++] = right;
//                if (dL <= sceneDist.x) stack[top++] = left;
//            } else {
//                if (dL <= sceneDist.x) stack[top++] = left;
//                if (dR <= sceneDist.x) stack[top++] = right;
//            }
//        }
//    }
//
//    return sceneDist;
//}

vec3 getPrimitiveNormal(Object object, vec3 pos) {
    const float h = EPSILON;
    return normalize(vec3(
        getObjectRaw(object, pos + vec3(h, 0, 0)) - getObjectRaw(object, pos - vec3(h, 0, 0)),
        getObjectRaw(object, pos + vec3(0, h, 0)) - getObjectRaw(object, pos - vec3(0, h, 0)),
        getObjectRaw(object, pos + vec3(0, 0, h)) - getObjectRaw(object, pos - vec3(0, 0, h))
    ));
}

//vec3 getPrimitiveNormal(Object object, vec3 pos) {
//    const float h = 0.005;
//    const vec3 k = vec3(1, -1, 0);
//    return normalize(
//    k.xyy * getObjectRaw(object, pos + k.xyy * h) +
//    k.yyx * getObjectRaw(object, pos + k.yyx * h) +
//    k.yxy * getObjectRaw(object, pos + k.yxy * h) +
//    k.xxx * getObjectRaw(object, pos + k.xxx * h)
//    );
//}

vec3 analyticNormal(Object object, vec3 p) {
    // compute local-space point
    vec3 lp = p - vec3(object.x, object.y, object.z);
    switch (object.objectType) {
        case 0: // Box
        {
            vec3 b = vec3(object.i, object.j, object.k);
            // normal is the sign of the largest component of abs(lp) - b
            vec3 d = abs(lp) - b;
            if (d.x > d.y && d.x > d.z) return vec3(sgn(lp.x), 0, 0);
            if (d.y > d.z)            return vec3(0, sgn(lp.y), 0);
            return                           vec3(0, 0, sgn(lp.z));
        }
        case 1: // Sphere
        return normalize(lp);
        case 2: // Cylinder (infinite along Y)
        // fCylinder is max(length(lp.xz)-r, abs(lp.y)-h)
        // lateral normal:
        if (abs(lp.y) < object.j) {
            return normalize(vec3(lp.x, 0, lp.z));    // side
        } else {
            return vec3(0, sgn(lp.y), 0);             // caps
        }
        case 3: // Cone
        {
            // For a right circular cone aligned on Y:
            // normal = normalize( vec3(lp.x, lp.y * (radius/height), lp.z) );
            float r = object.i, h = object.j;
            return normalize(vec3(lp.x, r/h * length(lp.xz), lp.z * r/h) );
        }
        case 4: // Torus
        {
            // torus normal = normalize(lp - vec3(length(lp.xz), 0, 0))
            float r = object.i, R = object.j;
            float d = length(lp.xz) - r;
            return normalize(vec3(d, lp.y, 0));
        }
        case 5: // Plane
        {
            // plane normal = vec3(0, 1, 0)
            return vec3(0, 1, 0);
        }
        case 6: // Capsule
        {
            // capsule normal = normalize(lp - vec3(0, lp.y, 0))
            float h = object.j;
            return normalize(vec3(0, lp.y, 0) - lp);
        }
        case 7: // Ellipsoid
        {
            // ellipsoid normal = normalize(lp / vec3(a, b, c))
            return normalize(vec3(lp.x / object.i, lp.y / object.j, lp.z / object.k));
        }
//        case 10: // Menger sponge
//        {
//            // Menger sponge normal = normalize(lp)
//            return normalize(lp);
//        }
//        case 11: // Mandelbulb
//        {
//            // Mandelbulb normal = normalize(lp)
//            return normalize(lp);
//        }
        default:
        // fallback: numerical (just once)
        return getPrimitiveNormal(object, p);
    }
    return vec3(0.0); // unreachable
}


//vec4 getNormal(vec3 pos) {
//    vec2 dist = calcSDF(pos);
//    vec3 rawNormal = analyticNormal(allObjects[int(dist.y)], pos);
//    return vec4(rawNormal, dist.y);
////    vec2 e = vec2(EPSILON, 0.0);
////
////    vec3 normal = dist.x - vec3(
////    calcSDF(pos-e.xyy).x,
////    calcSDF(pos-e.yxy).x,
////    calcSDF(pos-e.yyx).x);
////
////    return vec4(normalize(normal), dist.y);
//}

vec4 getNormal(vec3 pos) {
    // First we need to find the object ID by traversing the BVH
    float minDist = MAX_DIST_TO_TRAVEL;
    int foundObjID = -1;

    // Use a small loop to find the closest object at this position
    for (int nodeIdx = 0; nodeIdx < nodes.length(); nodeIdx++) {
        BVHNode node = nodes[nodeIdx];
        if (node.child.x < 0) { // Leaf node
            int start = node.child.z;
            int count = node.child.w;

            for (int i = 0; i < count; ++i) {
                int oid = objectIndices[start + i];
                Object o = allObjects[oid];
                float d = getObject(o, pos);

                if (d < minDist) {
                    minDist = d;
                    foundObjID = oid;
                }
            }
        }
    }

    vec3 rawNormal = analyticNormal(allObjects[foundObjID], pos);
    return vec4(rawNormal, float(foundObjID));
}