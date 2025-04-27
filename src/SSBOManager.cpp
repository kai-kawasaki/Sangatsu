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
    // Static full SSBO
    glGenBuffers(1, &_fullSSBO);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, _fullSSBO);
    size_t fullSize = sizeof(Object) * _maxObjects;
    // Immutable storage with initial data from _allObjects
    glBufferStorage(
      GL_SHADER_STORAGE_BUFFER,
      fullSize,
      _allObjects.data(),
      GL_DYNAMIC_STORAGE_BIT  // allows updates if needed
    );
    // Bind once to binding point 1
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, _fullSSBO);

    // Dynamic culled SSBO
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

    // leave no SSBO bound
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

    // bind *this* buffer for the draw
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, _ssbos[frame]);

    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
}


// SSBOManager::SSBOManager(const std::vector<Object>& allObjects)
//     : _allObjects(allObjects)
// {
//     // glGenBuffers(1, &_ssbo);
//     // glBindBuffer(GL_SHADER_STORAGE_BUFFER, _ssbo);
//     // glBufferData(GL_SHADER_STORAGE_BUFFER,
//     //              data.size()*sizeof(Object),
//     //              data.data(), GL_STATIC_DRAW);
//     // glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, _ssbo);
//     // glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
//
//
//     glGenBuffers(1, &_ssbo);
//     glBindBuffer(GL_SHADER_STORAGE_BUFFER, _ssbo);
//     size_t maxSize = sizeof(Object) * _allObjects.size();
//
//     // allocate persistent‐mapped buffer
//     glBufferStorage(
//         GL_SHADER_STORAGE_BUFFER,
//         maxSize,
//         nullptr,
//         GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT
//     );
//
//     _mappedPtr = static_cast<Object *>(glMapBufferRange(
//         GL_SHADER_STORAGE_BUFFER,
//         0,
//         maxSize,
//         GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT
//     ));
//
//     glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, _ssbo);
//
// }
//
// SSBOManager::~SSBOManager() {
//     glDeleteBuffers(1, &_ssbo);
// }
//
// void SSBOManager::update(const std::vector<Object>& data) const {
//     glBindBuffer(GL_SHADER_STORAGE_BUFFER, _ssbo);
//     glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0,
//                     data.size()*sizeof(Object), data.data());
//     glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
// }
//
// void SSBOManager::updateIndices(const std::vector<std::size_t>& indices) const {
//   for (size_t i = 0; i < indices.size(); ++i)
//     _mappedPtr[i] = _allObjects[indices[i]];
//   glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);
//
//     GLsync sync = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
//     glClientWaitSync(sync, GL_SYNC_FLUSH_COMMANDS_BIT, 1000000000);
//     glDeleteSync(sync);
//
// }
