//
// Created by kylez on 4/17/2025.
//

#include "SSBOManager.h"
#include "Globals.h"
#include <iostream>

// SSBOManager.cpp
SSBOManager::SSBOManager(const std::vector<Object>& allObjects)
: _maxObjects(allObjects.size())
, _allObjects(allObjects)
{
    // Static full SSBO - Not persistent (not continuously updated).
    glGenBuffers(1, &_fullSSBO);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, _fullSSBO);
    size_t fullSize = sizeof(Object) * _maxObjects;
    glBufferStorage(
      GL_SHADER_STORAGE_BUFFER,
      fullSize,
      _allObjects.data(),
      GL_DYNAMIC_STORAGE_BIT  // allows updates if needed
    );
    // Bind once to binding point 1
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, _fullSSBO);

    // Dynamic culled SSBO - Persistent mapped for high throughput (continuously updated).
    _ssbos.resize(FRAMES_IN_FLIGHT);
    _mappedPtrs.resize(FRAMES_IN_FLIGHT);

    glGenBuffers(FRAMES_IN_FLIGHT, _ssbos.data());
    for (int f = 0; f < FRAMES_IN_FLIGHT; ++f) {
        glBindBuffer(GL_SHADER_STORAGE_BUFFER, _ssbos[f]);

        size_t maxSize = sizeof(Object) * _maxObjects;
        glBufferStorage(
          GL_SHADER_STORAGE_BUFFER,
          maxSize,
          nullptr,
          GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT
        );

        // map once per-buffer
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
}

void SSBOManager::updateIndices(const std::vector<size_t>& indices, const int frame) const {
    Object* ptr = _mappedPtrs[frame];

    // pack front-to-back
    size_t count = std::min(indices.size(), _maxObjects);
    for (size_t i = 0; i < count; ++i)
        ptr[i] = _allObjects[indices[i]];

    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, _ssbos[frame]);

    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
}

// void SSBOManager::update(const std::vector<Object> &data) const {
//     glBindBuffer(GL_SHADER_STORAGE_BUFFER, _ssbo);
//     glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0,
//                     data.size() * sizeof(Object), data.data());
//     glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
// }