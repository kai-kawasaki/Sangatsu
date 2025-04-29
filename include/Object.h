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
    int textureXY; // texture ID for XY plane (side)
    int textureXZ; // texture ID for XZ plane (top)
    int textureYZ; // texture ID for YZ plane (front)
    float textureScale;
    Object(glm::vec3 position, glm::vec3 scale, int objectType, glm::vec3 color, int operation = 0, float blendRadius = 0, int groupLength = 0);
    Object(glm::vec3 position, glm::vec3 scale, int objectType, int materialID, float textureScale, int operation = 0, float blendRadius = 0, int groupLength = 0);
    Object(glm::vec3 position, glm::vec3 scale, int objectType, int textureXY, int textureXZ, int textureYZ, float textureScale, int operation = 0, float blendRadius = 0, int groupLength = 0);
};


#endif //OBJECT_H


// float x, y, z;
// float r, g, b;
// Object(float x, float y, float z, float r, float g, float b);