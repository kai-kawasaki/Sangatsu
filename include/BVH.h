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
    int left, right;   // children (-1 for leaf)
    int start, count;  // leaf: [start, start + count) in objectsIndices
    int parent;        // parent index (-1 for root)
};

struct BVHNodeSSBO {
    glm::vec4 boundsMin;   // xyz = min
    glm::vec4 boundsMax;   // xyz = max
    glm::ivec4 child;      // x = left, y = right, z = start, w = count
};

class BVHBuilder {
public:
    std::vector<BVHNode> nodes;
    std::vector<int> objectIndices;

    void build(const std::vector<Object>& objects, int leafSize = 4);
    void refit(const std::vector<Object>& objects,
               const std::vector<int>& dirtyObjects,
               int maxRefitPerFrame = -1,
               bool multithread = true);
    void rebuildIfNeeded(const std::vector<Object>& objects,
                         const std::vector<int>& dirtyObjects,
                         float rebuildRatio = 0.5f,
                         int leafSize = 4);
    void uploadInitial();
    void updateGPU();
    void updateGPU(int minNode, int maxNode);
    void bindBuffers() const;
    void cleanup();
    bool validate(const std::vector<Object>& objects, bool verbose = false) const;
private:
    int leafSize = 4;
    std::vector<int> objectToLeaf; // object index -> leaf index
    GLuint nodeSSBO = 0;
    GLuint indexSSBO = 0;
    BVHNodeSSBO* mappedNodes = nullptr;
    int* mappedIndices = nullptr;
    bool gpuAllocated = false;
    int minDirtyNode = -1;
    int maxDirtyNode = -1;

    int buildRecursive(int start, int end, const std::vector<Object>& objects);
    AABB computeBounds(int objIdx, const Object& o) const;
    void updateLeafBounds(int leafIdx, const std::vector<Object>& objects);
    void propagateBoundsUp(int nodeIdx);
    void ensureBuffers();
    void writeFullBuffers();
    void threadedUpdateLeaves(const std::vector<int>& leaves,
                              const std::vector<Object>& objects);
};


#endif //BVH_H
