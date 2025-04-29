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
    , textureScale(textureScale)
{

}
