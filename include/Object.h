//
// Created by kylez on 4/17/2025.
//

#ifndef OBJECT_H
#define OBJECT_H

#pragma once
#include <array>
#include <glm/fwd.hpp>
#include <glm/vec3.hpp>

struct Object {
    glm::vec3 position;
    glm::vec3 color;
    glm::vec3 scale;
    int objectType;
    int operation;
    float blendRadius;
    int groupLength;
    int materialID;
    float textureScale;
    Object(glm::vec3 position, glm::vec3 scale, int objectType, glm::vec3 color, int operation = 0, float blendRadius = 0, int groupLength = 0);
    Object(glm::vec3 position, glm::vec3 scale, int objectType, int materialID, float textureScale, int operation = 0, float blendRadius = 0, int groupLength = 0);
};


#endif //OBJECT_H


// float x, y, z;
// float r, g, b;
// Object(float x, float y, float z, float r, float g, float b);