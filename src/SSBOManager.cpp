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
