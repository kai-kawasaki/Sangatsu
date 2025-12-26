//
// Created by kylez on 4/17/2025.
//

#ifndef SSBOMANAGER_H
#define SSBOMANAGER_H

#pragma once
#include <vector>
#include <glad/glad.h>
#include "Object.h"

class SSBOManager {
public:
    SSBOManager(const std::vector<Object>& allObjects);
    ~SSBOManager();
    void updateIndices(const std::vector<size_t>& indices, int frame) const;
    // void update(const std::vector<Object>& data) const;
private:
    std::vector<GLuint>      _ssbos;
    std::vector<Object*>     _mappedPtrs;
    size_t                   _maxObjects;
    std::vector<Object>      _allObjects;
    GLuint                   _fullSSBO;
};


#endif //SSBOMANAGER_H
