//
// Created by kylez on 4/17/2025.
//

#include "RayMarcher.h"
#include <glm/gtc/type_ptr.hpp>
#include <vector>

RayMarcher::RayMarcher(Shader& s) : _shader(s), _vao(0), _vbo(0) {}

RayMarcher::~RayMarcher() {
    glDeleteBuffers(1, &_vbo);
    glDeleteVertexArrays(1, &_vao);
}

void RayMarcher::init() {
    glGenVertexArrays(1,&_vao);
    glGenBuffers(1,&_vbo);
    glBindVertexArray(_vao);
    glBindBuffer(GL_ARRAY_BUFFER,_vbo);
    glBufferData(GL_ARRAY_BUFFER,sizeof(_quad),_quad,GL_STATIC_DRAW);

    // auto posLoc = glGetAttribLocation(_shader.id(),"in_position");
    // auto colLoc = glGetAttribLocation(_shader.id(),"vCol");
    auto posLoc = 0;
    auto colLoc = 1;

    glEnableVertexAttribArray(posLoc);
    glVertexAttribPointer(posLoc,3,GL_FLOAT,GL_FALSE,
                          sizeof(Vertex),(void*)offsetof(Vertex,position));
    glEnableVertexAttribArray(colLoc);
    glVertexAttribPointer(colLoc,3,GL_FLOAT,GL_FALSE,
                          sizeof(Vertex),(void*)offsetof(Vertex,color));

    glBindVertexArray(0);
}

void RayMarcher::render(const float width, const float height,
                        const float time, const float scroll,
                        const glm::vec3& camPos,
                        const glm::vec3& camTarget,
                        const bool flashlightOn,
                        const int renderMode,
                        const GLuint textureID,
                        const int countObjects) const {
    _shader.use();
    glUniform2f(glGetUniformLocation(_shader.id(),"u_resolution"), width, height);
    glUniform1f(glGetUniformLocation(_shader.id(),"u_time"), time);
    glUniform1f(glGetUniformLocation(_shader.id(),"u_scroll"), scroll);
    glUniform3fv(glGetUniformLocation(_shader.id(),"u_camPos"),
                 1, glm::value_ptr(camPos));
    glUniform3fv(glGetUniformLocation(_shader.id(),"u_camTarget"),
                 1, glm::value_ptr(camTarget));
    glUniform1i(glGetUniformLocation(_shader.id(),"u_flashlight"), flashlightOn);
    glUniform1i(glGetUniformLocation(_shader.id(),"u_renderMode"), renderMode);
    glUniform1i(glGetUniformLocation(_shader.id(),"u_countObjects"), countObjects);

    struct Light {
        float size;
        glm::vec3 position;
        glm::vec3 color;
        glm::vec3 direction;
        float focus;
        float spread;
    };

    std::vector<Light> lights = {
        { 0.3f, {5.0f, 5.0f, 0.0f}, {0.8f, 0.7f, 0.6f}, {-1.0f, -1.0f, 0.0f}, 2.0f, 0.8f },
        { 0.2f, {-3.0f, 2.0f, 3.0f}, {0.1f, 0.15f, 0.5f}, {1.0f, -0.5f, -1.0f}, 1.5f, 0.6f }
    };

    // Send light count
    glUniform1i(glGetUniformLocation(_shader.id(), "u_lightCount"), static_cast<GLint>(lights.size()));

    // Send each light's properties
    for (size_t i = 0; i < lights.size(); ++i) {
        std::string base = "u_lights[" + std::to_string(i) + "].";
        glUniform1f(glGetUniformLocation(_shader.id(), (base + "size").c_str()), lights[i].size);
        glUniform3fv(glGetUniformLocation(_shader.id(), (base + "pos").c_str()), 1, glm::value_ptr(lights[i].position));
        glUniform3fv(glGetUniformLocation(_shader.id(), (base + "col").c_str()), 1, glm::value_ptr(lights[i].color));
        glUniform3fv(glGetUniformLocation(_shader.id(), (base + "dir").c_str()), 1, glm::value_ptr(lights[i].direction));
        glUniform1f(glGetUniformLocation(_shader.id(), (base + "focus").c_str()), lights[i].focus);
        glUniform1f(glGetUniformLocation(_shader.id(), (base + "spread").c_str()), lights[i].spread);
    }


    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, textureID);

    glBindVertexArray(_vao);
    glDrawArrays(GL_TRIANGLES,0,6);
    glBindVertexArray(0);
}
