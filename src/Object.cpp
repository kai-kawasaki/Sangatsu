//
// Created by kylez on 4/17/2025.
//

#include "Object.h"

Object::Object(const glm::vec3 position, const glm::vec3 scale, const int objectType, const glm::vec3 color, const int operation, const float blendRadius, const int groupLength)
    : position(position)
    , color(color)
    , scale(scale)
    , objectType(objectType)
    , operation(operation)
    , blendRadius(blendRadius)
    , groupLength(groupLength)
    , materialID(-1)
    , textureXY(0)
    , textureXZ(0)
    , textureYZ(0)
    , textureScale(0.0f)
{
    // Constructor implementation
}

Object::Object(const glm::vec3 position, const glm::vec3 scale, const int objectType, const int materialID, const float textureScale, const int operation, const float blendRadius, const int groupLength)
    : position(position)
    , color(glm::vec3(0))
    , scale(scale)
    , objectType(objectType)
    , operation(operation)
    , blendRadius(blendRadius)
    , groupLength(groupLength)
    , materialID(materialID)
    , textureXY(0)
    , textureXZ(0)
    , textureYZ(0)
    , textureScale(textureScale)
{

}

Object::Object(glm::vec3 position, glm::vec3 scale, int objectType, int textureXY, int textureXZ, int textureYZ, float textureScale, int operation, float blendRadius, int groupLength)
    : position(position)
    , color(glm::vec3(0))
    , scale(scale)
    , objectType(objectType)
    , operation(operation)
    , blendRadius(blendRadius)
    , groupLength(groupLength)
    , materialID(-2)
    , textureXY(textureXY)
    , textureXZ(textureXZ)
    , textureYZ(textureYZ)
    , textureScale(textureScale)
{

}

