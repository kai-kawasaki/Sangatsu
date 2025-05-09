//
// Created by kylez on 5/9/2025.
//

#include "BVH.h"

#include <algorithm>
#include <numeric>

static AABB mergeBounds(const AABB &a, const AABB &b) {
    return {
        glm::min(a.min, b.min),
        glm::max(a.max, b.max)
    };
}

void BVHBuilder::build(const std::vector<Object> &objects, const int leafSize) {
    this->leafSize = leafSize;
    objectIndices.resize(objects.size());
    std::iota(objectIndices.begin(), objectIndices.end(), 0);

    nodes.clear();
    nodes.reserve(objects.size() * 2); // reserve space for all nodes

    buildRecursive(0, static_cast<int>(objects.size()), objects);
}

AABB BVHBuilder::computeBounds(int objIdx, const Object &o) {
    AABB b;
    glm::vec3 p = o.position;
    // 0 = box
    // 1 = sphere
    // 2 = cylinder
    // 3 = cone
    // 4 = torus
    // 5 = plane
    // 6 = capsule
    // 7 = ellipsoid
    // 10 = menger sponge
    switch (o.objectType) {
        case 0: { // box
            b.min = p - o.scale;
            b.max = p + o.scale;
            break;
        }
        case 1: { // sphere
            b.min = p - glm::vec3(o.scale.x);
            b.max = p + glm::vec3(o.scale.x);
            break;
        }
        case 2: { // cylinder (axis = Y)
            b.min = p - glm::vec3(o.scale.x, o.scale.y, o.scale.x);
            b.max = p + glm::vec3(o.scale.x, o.scale.y, o.scale.x);
            break;
        }
        case 3: { // cone (axis = Y)
            b.min = p - glm::vec3(o.scale.x, 0.0f, o.scale.x);
            b.max = p + glm::vec3(o.scale.x, o.scale.y, o.scale.x);
            break;
        }
        case 4: { // torus (major = x, minor = y)
            float a = o.scale.x;
            float r = o.scale.y;
            glm::vec3 ext(a + r, r, a + r);
            b.min = p - ext;
            b.max = p + ext;
            break;
        }
        case 5: { // plane (infinite)
            b.min = glm::vec3(-std::numeric_limits<float>::infinity());
            b.max = glm::vec3( std::numeric_limits<float>::infinity());
            break;
        }
        case 6: { // capsule (axis = Y)
            float r = o.scale.x;
            float h = o.scale.y;
            b.min = p - glm::vec3(r, h + r, r);
            b.max = p + glm::vec3(r, h + r, r);
            break;
        }
        case 7: { // ellipsoid
            b.min = p - o.scale;
            b.max = p + o.scale;
            break;
        }
        case 10: { // Menger fractal (approximate as cube)
            b.min = p - glm::vec3(o.scale.x);
            b.max = p + glm::vec3(o.scale.x);
            break;
        }
        default: {
            b.min = p;
            b.max = p;
            break;
        }
    }
    return b;
}

int BVHBuilder::buildRecursive(int start, int end, const std::vector<Object>& objects) {
    int nodeIndex = static_cast<int>(nodes.size());
    nodes.push_back(BVHNode());
    BVHNode& node = nodes.back();

    // compute bounds over range
    int first = objectIndices[start];
    AABB bounds = computeBounds(first, objects[first]);
    for (int i = start + 1; i < end; ++i) {
        int idx = objectIndices[i];
        bounds = mergeBounds(bounds, computeBounds(idx, objects[idx]));
    }
    node.bounds = bounds;

    int count = end - start;
    if (count <= leafSize) {
        // leaf node
        node.left  = -1;
        node.right = -1;
        node.start = start;
        node.count = count;
    } else {
        // pick longest axis
        glm::vec3 ext = bounds.max - bounds.min;
        int axis = (ext.x > ext.y && ext.x > ext.z) ? 0
                   : (ext.y > ext.z)             ? 1
                   : 2;

        // sort by centroid on that axis
        std::sort(objectIndices.begin() + start,
                  objectIndices.begin() + end,
                  [&](int a, int b) {
                      AABB ba = computeBounds(a, objects[a]);
                      AABB bb = computeBounds(b, objects[b]);
                      float ca = 0.5f * (ba.min[axis] + ba.max[axis]);
                      float cb = 0.5f * (bb.min[axis] + bb.max[axis]);
                      return ca < cb;
                  });

        int mid = start + count / 2;
        node.start = -1;
        node.count = 0;
        node.left  = buildRecursive(start, mid, objects);
        node.right = buildRecursive(mid, end, objects);
    }

    return nodeIndex;
}

void BVHBuilder::generateSSBO() const {
    GLuint bvhNodeSSBO;
    glGenBuffers(1, &bvhNodeSSBO);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, bvhNodeSSBO);
    glBufferData(
        GL_SHADER_STORAGE_BUFFER,
        nodes.size() * sizeof(BVHNode),
        nodes.data(),
        GL_STATIC_DRAW
    );
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, bvhNodeSSBO);

    GLuint bvhIndexSSBO;
    glGenBuffers(1, &bvhIndexSSBO);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, bvhIndexSSBO);
    glBufferData(
        GL_SHADER_STORAGE_BUFFER,
        objectIndices.size() * sizeof(int),
        objectIndices.data(),
        GL_STATIC_DRAW
    );
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 3, bvhIndexSSBO);
}
