//
// Created by kylez on 5/9/2025.
//

#include "BVH.h"

#include <algorithm>
#include <future>
#include <iostream>
#include <limits>
#include <numeric>
#include <thread>

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
    nodes.reserve(objects.size() * 2);
    objectToLeaf.assign(objects.size(), -1);

    buildRecursive(0, static_cast<int>(objects.size()), objects);

    minDirtyNode = 0;
    maxDirtyNode = static_cast<int>(nodes.size()) - 1;
}

AABB BVHBuilder::computeBounds(const int objIdx, const Object &o) const {
    AABB b{};
    const glm::vec3 p = o.position;

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
        case 11: {
            float r = o.scale.x * 2.0f;
            b.min = p - glm::vec3(r);
            b.max = p + glm::vec3(r);
            break;
        }
        default: {
            b.min = p;
            b.max = p;
            break;
        }
    }

    if (o.heightID >= 0 && o.displacementStrength > 0.0f) {
        b.min -= glm::vec3(o.displacementStrength);
        b.max += glm::vec3(o.displacementStrength);
    }

    return b;
}

int BVHBuilder::buildRecursive(const int start, const int end, const std::vector<Object>& objects) {
    const int nodeIndex = static_cast<int>(nodes.size());
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
    node.parent = -1;

    const int count = end - start;
    if (count <= leafSize) {
        node.left  = -1;
        node.right = -1;
        node.start = start;
        node.count = count;

        for (int i = 0; i < count; ++i) {
            const int objIdx = objectIndices[start + i];
            if (objIdx >= 0 && objIdx < static_cast<int>(objectToLeaf.size())) {
                objectToLeaf[objIdx] = nodeIndex;
            }
        }
    } else {
        glm::vec3 ext = bounds.max - bounds.min;
        const int axis = (ext.x > ext.y && ext.x > ext.z) ? 0
                       : (ext.y > ext.z)                  ? 1
                                                         : 2;

        std::sort(objectIndices.begin() + start,
                  objectIndices.begin() + end,
                  [&](const int a, const int b) {
                      const AABB ba = computeBounds(a, objects[a]);
                      const AABB bb = computeBounds(b, objects[b]);
                      const float ca = 0.5f * (ba.min[axis] + ba.max[axis]);
                      const float cb = 0.5f * (bb.min[axis] + bb.max[axis]);
                      return ca < cb;
                  });

        const int mid = start + count / 2;
        node.start = -1;
        node.count = 0;
        node.left  = buildRecursive(start, mid, objects);
        node.right = buildRecursive(mid, end, objects);
        nodes[node.left].parent  = nodeIndex;
        nodes[node.right].parent = nodeIndex;
    }

    return nodeIndex;
}

void BVHBuilder::updateLeafBounds(const int leafIdx, const std::vector<Object>& objects) {
    if (leafIdx < 0 || leafIdx >= static_cast<int>(nodes.size())) return;
    BVHNode& node = nodes[leafIdx];
    if (node.left >= 0) return; // not a leaf

    int firstObj = objectIndices[node.start];
    AABB bounds = computeBounds(firstObj, objects[firstObj]);
    for (int i = 1; i < node.count; ++i) {
        const int objIdx = objectIndices[node.start + i];
        bounds = mergeBounds(bounds, computeBounds(objIdx, objects[objIdx]));
    }
    node.bounds = bounds;
    if (minDirtyNode < 0 || leafIdx < minDirtyNode) minDirtyNode = leafIdx;
    if (leafIdx > maxDirtyNode) maxDirtyNode = leafIdx;
}

void BVHBuilder::propagateBoundsUp(int nodeIdx) {
    int current = nodeIdx;
    while (current >= 0) {
        BVHNode& n = nodes[current];
        if (n.left >= 0 && n.right >= 0) {
            n.bounds = mergeBounds(nodes[n.left].bounds, nodes[n.right].bounds);
        }
        if (minDirtyNode < 0 || current < minDirtyNode) minDirtyNode = current;
        if (current > maxDirtyNode) maxDirtyNode = current;
        current = n.parent;
    }
}

void BVHBuilder::threadedUpdateLeaves(const std::vector<int>& leaves,
                                      const std::vector<Object>& objects) {
    if (leaves.empty()) return;
    const std::size_t workerCount = std::max(1u, std::thread::hardware_concurrency());
    const std::size_t chunk = (leaves.size() + workerCount - 1) / workerCount;

    std::vector<AABB> computed(leaves.size());
    std::vector<std::future<void>> jobs;
    jobs.reserve(workerCount);

    for (std::size_t w = 0; w < workerCount; ++w) {
        const std::size_t begin = w * chunk;
        if (begin >= leaves.size()) break;
        const std::size_t end = std::min(leaves.size(), begin + chunk);
        jobs.push_back(std::async(std::launch::async, [&, begin, end]() {
            for (std::size_t i = begin; i < end; ++i) {
                const int leafIdx = leaves[i];
                if (leafIdx < 0 || leafIdx >= static_cast<int>(nodes.size())) continue;
                const BVHNode& n = nodes[leafIdx];
                int firstObj = objectIndices[n.start];
                AABB bounds = computeBounds(firstObj, objects[firstObj]);
                for (int j = 1; j < n.count; ++j) {
                    const int objIdx = objectIndices[n.start + j];
                    bounds = mergeBounds(bounds, computeBounds(objIdx, objects[objIdx]));
                }
                computed[i] = bounds;
            }
        }));
    }

    for (auto& j : jobs) j.wait();

    for (std::size_t i = 0; i < leaves.size(); ++i) {
        const int leafIdx = leaves[i];
        if (leafIdx < 0 || leafIdx >= static_cast<int>(nodes.size())) continue;
        nodes[leafIdx].bounds = computed[i];
        if (minDirtyNode < 0 || leafIdx < minDirtyNode) minDirtyNode = leafIdx;
        if (leafIdx > maxDirtyNode) maxDirtyNode = leafIdx;
    }
}

void BVHBuilder::refit(const std::vector<Object>& objects,
                       const std::vector<int>& dirtyObjects,
                       const int maxRefitPerFrame,
                       const bool multithread) {
    if (nodes.empty()) return;
    if (dirtyObjects.empty()) return;

    std::vector<int> leaves;
    leaves.reserve(dirtyObjects.size());
    int processed = 0;
    for (int obj : dirtyObjects) {
        if (maxRefitPerFrame > 0 && processed >= maxRefitPerFrame) break;
        if (obj < 0 || obj >= static_cast<int>(objectToLeaf.size())) continue;
        const int leafIdx = objectToLeaf[obj];
        if (leafIdx >= 0) {
            leaves.push_back(leafIdx);
            ++processed;
        }
    }

    std::sort(leaves.begin(), leaves.end());
    leaves.erase(std::unique(leaves.begin(), leaves.end()), leaves.end());

    if (leaves.empty()) return;

    if (multithread && leaves.size() > 4) {
        threadedUpdateLeaves(leaves, objects);
    } else {
        for (const int leafIdx : leaves) updateLeafBounds(leafIdx, objects);
    }

    for (const int leafIdx : leaves) propagateBoundsUp(leafIdx);
}

void BVHBuilder::rebuildIfNeeded(const std::vector<Object>& objects,
                                 const std::vector<int>& dirtyObjects,
                                 const float rebuildRatio,
                                 const int requestedLeafSize) {
    const float ratio = static_cast<float>(dirtyObjects.size()) /
                        static_cast<float>(std::max<std::size_t>(1, objects.size()));
    const bool needsRebuild = ratio >= rebuildRatio ||
                              static_cast<int>(objects.size()) != static_cast<int>(objectIndices.size());
    if (!needsRebuild) return;

    build(objects, requestedLeafSize);
    writeFullBuffers();
    bindBuffers();
}

void BVHBuilder::ensureBuffers() {
    if (gpuAllocated) return;

    glGenBuffers(1, &nodeSSBO);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, nodeSSBO);
    const std::size_t maxNodesBytes = std::max<std::size_t>(1, nodes.size()) * sizeof(BVHNodeSSBO);
    glBufferStorage(
        GL_SHADER_STORAGE_BUFFER,
        maxNodesBytes,
        nullptr,
        GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT | GL_DYNAMIC_STORAGE_BIT
    );
    mappedNodes = static_cast<BVHNodeSSBO*>(glMapBufferRange(
        GL_SHADER_STORAGE_BUFFER,
        0,
        maxNodesBytes,
        GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT
    ));

    glGenBuffers(1, &indexSSBO);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, indexSSBO);
    const std::size_t maxIndexBytes = std::max<std::size_t>(1, objectIndices.size()) * sizeof(int);
    glBufferStorage(
        GL_SHADER_STORAGE_BUFFER,
        maxIndexBytes,
        nullptr,
        GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT | GL_DYNAMIC_STORAGE_BIT
    );
    mappedIndices = static_cast<int*>(glMapBufferRange(
        GL_SHADER_STORAGE_BUFFER,
        0,
        maxIndexBytes,
        GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT
    ));

    gpuAllocated = true;
}

void BVHBuilder::writeFullBuffers() {
    ensureBuffers();
    if (!mappedNodes || !mappedIndices) return;

    std::vector<BVHNodeSSBO> nodesSSBO;
    nodesSSBO.reserve(nodes.size());
    for (const auto& node : nodes) {
        BVHNodeSSBO n{};
        n.boundsMin = glm::vec4(node.bounds.min, 0.0f);
        n.boundsMax = glm::vec4(node.bounds.max, 0.0f);
        n.child     = glm::ivec4(node.left, node.right, node.start, node.count);
        nodesSSBO.push_back(n);
    }

    std::copy(nodesSSBO.begin(), nodesSSBO.end(), mappedNodes);
    std::copy(objectIndices.begin(), objectIndices.end(), mappedIndices);

    glMemoryBarrier(GL_CLIENT_MAPPED_BUFFER_BARRIER_BIT | GL_SHADER_STORAGE_BARRIER_BIT);
    minDirtyNode = 0;
    maxDirtyNode = static_cast<int>(nodes.size()) - 1;
}

void BVHBuilder::uploadInitial() {
    writeFullBuffers();
    bindBuffers();
}

void BVHBuilder::updateGPU() {
    if (minDirtyNode < 0 || maxDirtyNode < 0 || nodes.empty()) return;
    updateGPU(minDirtyNode, maxDirtyNode);
    minDirtyNode = -1;
    maxDirtyNode = -1;
}

void BVHBuilder::updateGPU(const int minNode, const int maxNode) {
    if (!mappedNodes || nodes.empty()) return;
    const int clampedMin = std::max(0, minNode);
    const int clampedMax = std::min(static_cast<int>(nodes.size()) - 1, maxNode);
    if (clampedMin > clampedMax) return;

    std::vector<BVHNodeSSBO> nodesSSBO;
    nodesSSBO.reserve(static_cast<std::size_t>(clampedMax - clampedMin + 1));
    for (int i = clampedMin; i <= clampedMax; ++i) {
        const auto& node = nodes[i];
        BVHNodeSSBO n{};
        n.boundsMin = glm::vec4(node.bounds.min, 0.0f);
        n.boundsMax = glm::vec4(node.bounds.max, 0.0f);
        n.child     = glm::ivec4(node.left, node.right, node.start, node.count);
        nodesSSBO.push_back(n);
    }

    std::copy(nodesSSBO.begin(), nodesSSBO.end(), mappedNodes + clampedMin);
    glMemoryBarrier(GL_CLIENT_MAPPED_BUFFER_BARRIER_BIT | GL_SHADER_STORAGE_BARRIER_BIT);
}

void BVHBuilder::bindBuffers() const {
    if (!gpuAllocated) return;
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, nodeSSBO);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, indexSSBO);
}

void BVHBuilder::cleanup() {
    if (mappedNodes) {
        glBindBuffer(GL_SHADER_STORAGE_BUFFER, nodeSSBO);
        glUnmapBuffer(GL_SHADER_STORAGE_BUFFER);
    }
    if (mappedIndices) {
        glBindBuffer(GL_SHADER_STORAGE_BUFFER, indexSSBO);
        glUnmapBuffer(GL_SHADER_STORAGE_BUFFER);
    }
    if (nodeSSBO) glDeleteBuffers(1, &nodeSSBO);
    if (indexSSBO) glDeleteBuffers(1, &indexSSBO);
    mappedNodes = nullptr;
    mappedIndices = nullptr;
    nodeSSBO = 0;
    indexSSBO = 0;
    gpuAllocated = false;
}

bool BVHBuilder::validate(const std::vector<Object>& objects, const bool verbose) const {
    bool ok = true;
    for (std::size_t i = 0; i < nodes.size(); ++i) {
        const auto& n = nodes[i];
        AABB expected{};
        if (n.left < 0) {
            if (n.count <= 0) continue;
            int firstObj = objectIndices[n.start];
            expected = computeBounds(firstObj, objects[firstObj]);
            for (int j = 1; j < n.count; ++j) {
                int objIdx = objectIndices[n.start + j];
                expected = mergeBounds(expected, computeBounds(objIdx, objects[objIdx]));
            }
        } else {
            expected = mergeBounds(nodes[n.left].bounds, nodes[n.right].bounds);
        }

        const bool mismatch = glm::any(glm::greaterThan(expected.min, n.bounds.min + glm::vec3(1e-3f))) ||
                              glm::any(glm::lessThan(expected.min, n.bounds.min - glm::vec3(1e-3f))) ||
                              glm::any(glm::greaterThan(expected.max, n.bounds.max + glm::vec3(1e-3f))) ||
                              glm::any(glm::lessThan(expected.max, n.bounds.max - glm::vec3(1e-3f)));
        if (mismatch) {
            ok = false;
            if (verbose) {
                std::cerr << "BVH node mismatch at " << i << " expected ["
                          << expected.min.x << ", " << expected.min.y << ", " << expected.min.z << "] -> ["
                          << expected.max.x << ", " << expected.max.y << ", " << expected.max.z << "] got ["
                          << n.bounds.min.x << ", " << n.bounds.min.y << ", " << n.bounds.min.z << "] -> ["
                          << n.bounds.max.x << ", " << n.bounds.max.y << ", " << n.bounds.max.z << "]\n";
            }
        }
    }
    return ok;
}
