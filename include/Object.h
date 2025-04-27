//
// Created by kylez on 4/17/2025.
//

#ifndef OBJECT_H
#define OBJECT_H

#pragma once
#include <glm/vec3.hpp>

struct Object {
    glm::vec3 position;
    glm::vec3 color;
    // float x, y, z;
    // float r, g, b;
    // Object(float x, float y, float z, float r, float g, float b);
    Object(glm::vec3 position, glm::vec3 color);
};


#endif //OBJECT_H
