//
// Created by kylez on 5/8/2025.
//

#ifndef BVH_H
#define BVH_H

#include <vector>
#include <glm/glm.hpp>
#include "Object.h"
#include <glad/glad.h>

struct AABB {
    glm::vec3 min, max;
};

struct BVHNode {
    AABB bounds;
    int left, right; // children (-1 for leaf)
    int start, count; // leaf: [start, start + count) in objectsIndices
};

class BVHBuilder {
public:
    std::vector<BVHNode> nodes;
    std::vector<int> objectIndices;


    void build(const std::vector<Object>& objects, int leafSize = 4);
    void generateSSBO() const;
private:
    int leafSize;
    int buildRecursive(int start, int end, const std::vector<Object>& objects);
    AABB computeBounds(int objIdx, const Object& o);
};


#endif //BVH_H
