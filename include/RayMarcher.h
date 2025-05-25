//
// Created by kylez on 4/17/2025.
//

#ifndef RAYMARCHER_H
#define RAYMARCHER_H

#pragma once
#include "Shader.h"
#include "Vertex.h"
#include <glad/gl.h>

class RayMarcher {
public:
    RayMarcher(Shader& shader);
    ~RayMarcher();

    void render(float width, float height,
                float time, float scroll,
                const glm::vec3& camPos,
                const glm::vec3& camTarget,
                bool flashlightOn,
                int renderMode,
                const glm::vec3& lightPos,
                int countObjects = 0) const;

private:
    Shader& _shader;
};

#endif //RAYMARCHER_H
