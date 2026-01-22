//
// Created by kylez on 4/17/2025.
//

#include "SSBOManager.h"
#include "Globals.h"
#include <iostream>

SSBOManager::SSBOManager(const std::vector<Object>& allObjects)
: _maxObjects(allObjects.size())
, _allObjects(allObjects)
{
    glGenBuffers(1, &_fullSSBO);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, _fullSSBO);
    const size_t fullSize = sizeof(Object) * _maxObjects;
    glBufferStorage(
      GL_SHADER_STORAGE_BUFFER,
      fullSize,
      _allObjects.data(),
      GL_DYNAMIC_STORAGE_BIT
    );
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, _fullSSBO);

    _ssbos.resize(FRAMES_IN_FLIGHT);
    _mappedPtrs.resize(FRAMES_IN_FLIGHT);

    glGenBuffers(FRAMES_IN_FLIGHT, _ssbos.data());
    for (int f = 0; f < FRAMES_IN_FLIGHT; ++f) {
        glBindBuffer(GL_SHADER_STORAGE_BUFFER, _ssbos[f]);

        const size_t maxSize = sizeof(Object) * _maxObjects;
        glBufferStorage(
          GL_SHADER_STORAGE_BUFFER,
          maxSize,
          nullptr,
          GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT
        );

        _mappedPtrs[f] = static_cast<Object*>(
          glMapBufferRange(
            GL_SHADER_STORAGE_BUFFER,
            0, maxSize,
            GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT
          )
        );
    }

    glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
}

SSBOManager::~SSBOManager() {
    for (auto& id : _ssbos) glDeleteBuffers(1, &id);
    if (_fullSSBO) glDeleteBuffers(1, &_fullSSBO);
}

void SSBOManager::syncAllObjects(const std::vector<Object>& allObjects) {
    if (allObjects.empty()) return;

    const bool needsResize = allObjects.size() > _maxObjects;
    _allObjects = allObjects;
    _maxObjects = _allObjects.size();

    glBindBuffer(GL_SHADER_STORAGE_BUFFER, _fullSSBO);
    const size_t newSize = sizeof(Object) * _maxObjects;
    if (needsResize) {
        glBufferData(GL_SHADER_STORAGE_BUFFER, newSize, _allObjects.data(), GL_DYNAMIC_DRAW);
    } else {
        glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0, newSize, _allObjects.data());
    }
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
}

void SSBOManager::updateIndices(const std::vector<size_t>& indices, const int frame) const {
    if (_ssbos.empty()) return;
    Object* ptr = _mappedPtrs[frame];
    if (!ptr) return;

    const size_t count = std::min(indices.size(), _maxObjects);
    for (size_t i = 0; i < count; ++i)
        ptr[i] = _allObjects[indices[i]];

    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, _ssbos[frame]);
    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
}
