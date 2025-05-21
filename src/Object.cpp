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
    , albedoID(-1)
    , normalID(-1)
    , metallicID(-1)
    , roughnessID(-1)
    , aoID(-1)
    , heightID(-1)
    , displacementStrength(0.0f)
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
    , albedoID(-1)
    , normalID(-1)
    , metallicID(-1)
    , roughnessID(-1)
    , aoID(-1)
    , heightID(-1)
    , displacementStrength(0.0f)
{

}

Object::Object(glm::vec3 position, glm::vec3 scale, int objectType, int materialID, std::string texture, Texture &textures, float textureScale, float displacementStrength, int operation, float blendRadius, int groupLength)
    : position(position)
    , color(glm::vec3(0))
    , scale(scale)
    , objectType(objectType)
    , operation(operation)
    , blendRadius(blendRadius)
    , groupLength(groupLength)
    , materialID(materialID)
    , textureScale(textureScale)
    // , albedoID(albedoID)
    // , normalID(normalID)
    // , metallicID(metallicID)
    // , roughnessID(roughnessID)
    // , aoID(aoID)
    // , heightID(heightID)
    , displacementStrength(displacementStrength)
{
    albedoID = textures.getTextureID(texture + "_albedo");
    normalID = textures.getTextureID(texture + "_normal");
    metallicID = textures.getTextureID(texture + "_metallic");
    roughnessID = textures.getTextureID(texture + "_roughness");
    aoID = textures.getTextureID(texture + "_ao");
    heightID = textures.getTextureID(texture + "_height");
}

