//
// Created by kylez on 4/17/2025.
//

#include "SSBOManager.h"
#include <iostream>

SSBOManager::SSBOManager(const std::vector<Object>& data) {
    glGenBuffers(1, &_ssbo);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, _ssbo);
    glBufferData(GL_SHADER_STORAGE_BUFFER,
                 data.size()*sizeof(Object),
                 data.data(), GL_STATIC_DRAW);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, _ssbo);
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);

    //TODO: add persistent mapping

    // glGenBuffers(1, &_ssbo);
    // glBindBuffer(GL_SHADER_STORAGE_BUFFER, _ssbo);
    // size_t maxSize = sizeof(Object) * data.size();
    //
    // // allocate persistent‐mapped buffer
    // glBufferStorage(
    //     GL_SHADER_STORAGE_BUFFER,
    //     maxSize,
    //     nullptr,
    //     GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT
    // );
    //
    // _mappedPtr = (Object*)glMapBufferRange(
    //     GL_SHADER_STORAGE_BUFFER,
    //     0,
    //     maxSize,
    //     GL_MAP_WRITE_BIT | GL_MAP_PERSISTENT_BIT | GL_MAP_COHERENT_BIT
    // );
}

SSBOManager::~SSBOManager() {
    glDeleteBuffers(1, &_ssbo);
}

void SSBOManager::update(const std::vector<Object>& data) const {
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, _ssbo);
    glBufferSubData(GL_SHADER_STORAGE_BUFFER, 0,
                    data.size()*sizeof(Object), data.data());
    glBindBuffer(GL_SHADER_STORAGE_BUFFER, 0);
}
