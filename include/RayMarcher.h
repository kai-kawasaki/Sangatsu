//
// Created by kylez on 4/17/2025.
//

#ifndef RAYMARCHER_H
#define RAYMARCHER_H

#pragma once
#include "Shader.h"
#include "Vertex.h"
#include <glad/glad.h>

class RayMarcher {
public:
    RayMarcher(Shader& shader);
    ~RayMarcher();

    void init();
    void render(float width, float height,
                float time, float scroll,
                const glm::vec3& camPos,
                const glm::vec3& camTarget,
                bool flashlightOn,
                int renderMode,
                GLuint textureID,
                int countObjects = 0) const;

private:
    Shader& _shader;
    GLuint _vao, _vbo;

    static inline const Vertex _quad[6] = {
        {{-1,-1,0},{1,0,0}},{{1,-1,0},{0,1,0}},{{1,1,0},{0,0,1}},
        {{-1,-1,0},{1,0,0}},{{1,1,0},{0,0,1}},{{-1,1,0},{1,1,0}}
    };
};

#endif //RAYMARCHER_H
