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
    explicit SSBOManager(const std::vector<Object>& data);
    ~SSBOManager();

    void update(const std::vector<Object>& data) const;

private:
    GLuint _ssbo{};
};

#endif //SSBOMANAGER_H
