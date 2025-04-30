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
    , albedoID(-1)
    , normalID(-1)
    , metallicID(-1)
    , roughnessID(-1)
    , aoID(-1)
    , heightID(-1)
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
    , albedoID(-1)
    , normalID(-1)
    , metallicID(-1)
    , roughnessID(-1)
    , aoID(-1)
    , heightID(-1)
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
    , albedoID(-1)
    , normalID(-1)
    , metallicID(-1)
    , roughnessID(-1)
    , aoID(-1)
    , heightID(-1)
{

}

Object::Object(glm::vec3 position, glm::vec3 scale, int objectType, int materialID, int albedoID, int normalID, int metallicID, int roughnessID, int aoID, int heightID, float textureScale, int operation, float blendRadius, int groupLength)
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
    , albedoID(albedoID)
    , normalID(normalID)
    , metallicID(metallicID)
    , roughnessID(roughnessID)
    , aoID(aoID)
    , heightID(heightID)
{
}

