//
// Created by kylez on 4/17/2025.
//

#include "RayMarcher.h"
#include <glm/gtc/type_ptr.hpp>

RayMarcher::RayMarcher(Shader& shader) : _shader(shader) {}

RayMarcher::~RayMarcher() {
}

// void RayMarcher::init() {
//     glGenVertexArrays(1,&_vao);
//     glGenBuffers(1,&_vbo);
//     glBindVertexArray(_vao);
//     glBindBuffer(GL_ARRAY_BUFFER,_vbo);
//     glBufferData(GL_ARRAY_BUFFER,sizeof(_quad),_quad,GL_STATIC_DRAW);
//
//     // auto posLoc = glGetAttribLocation(_shader.id(),"in_position");
//     // auto colLoc = glGetAttribLocation(_shader.id(),"vCol");
//     auto posLoc = 0;
//     auto colLoc = 1;
//
//     glEnableVertexAttribArray(posLoc);
//     glVertexAttribPointer(posLoc,3,GL_FLOAT,GL_FALSE,
//                           sizeof(Vertex),(void*)offsetof(Vertex,position));
//     glEnableVertexAttribArray(colLoc);
//     glVertexAttribPointer(colLoc,3,GL_FLOAT,GL_FALSE,
//                           sizeof(Vertex),(void*)offsetof(Vertex,color));
//
//     glBindVertexArray(0);
// }

// void RayMarcher::render(const float width, const float height,
//                         const float time, const float scroll,
//                         const glm::vec3& camPos,
//                         const glm::vec3& camTarget,
//                         const bool flashlightOn,
//                         const int renderMode,
//                         const GLuint textureID,
//                         const glm::vec3& lightPos,
//                         const int countObjects) const {
//     _shader.use();
//     glUniform2f(glGetUniformLocation(_shader.id(),"u_resolution"), width, height);
//     glUniform1f(glGetUniformLocation(_shader.id(),"u_time"), time);
//     glUniform1f(glGetUniformLocation(_shader.id(),"u_scroll"), scroll);
//     glUniform3fv(glGetUniformLocation(_shader.id(),"u_camPos"),
//                  1, glm::value_ptr(camPos));
//     glUniform3fv(glGetUniformLocation(_shader.id(),"u_camTarget"),
//                  1, glm::value_ptr(camTarget));
//     glUniform1i(glGetUniformLocation(_shader.id(),"u_flashlight"), flashlightOn);
//     glUniform1i(glGetUniformLocation(_shader.id(),"u_renderMode"), renderMode);
//     glUniform1i(glGetUniformLocation(_shader.id(),"u_countObjects"), countObjects);
//     glUniform3fv(glGetUniformLocation(_shader.id(),"u_lightPos"), 1, glm::value_ptr(lightPos));
//
//     glActiveTexture(GL_TEXTURE0);
//     glBindTexture(GL_TEXTURE_2D, textureID);
//
//     glBindVertexArray(_vao);
//     glDrawArrays(GL_TRIANGLES,0,6);
//     glBindVertexArray(0);
// }

void RayMarcher::render(const float width, const float height,
                        const float time, const float scroll,
                        const glm::vec3& camPos,
                        const glm::vec3& camTarget,
                        const bool flashlightOn,
                        const int renderMode,
                        const glm::vec3& lightPos,
                        const int countObjects) const
{
    // 1) bind and set uniforms on compute shader
    _shader.use();
    glUniform2f(glGetUniformLocation(_shader.id(), "u_resolution"),
                width, height);
    glUniform1f(glGetUniformLocation(_shader.id(), "u_time"), time);
    glUniform1f(glGetUniformLocation(_shader.id(), "u_scroll"), scroll);
    glUniform3fv(glGetUniformLocation(_shader.id(), "u_camPos"),
                 1, glm::value_ptr(camPos));
    glUniform3fv(glGetUniformLocation(_shader.id(), "u_camTarget"),
                 1, glm::value_ptr(camTarget));
    glUniform1i(glGetUniformLocation(_shader.id(), "u_flashlight"),
                flashlightOn);
    glUniform1i(glGetUniformLocation(_shader.id(), "u_renderMode"),
                renderMode);
    glUniform1i(glGetUniformLocation(_shader.id(), "u_countObjects"),
                countObjects);
    glUniform3fv(glGetUniformLocation(_shader.id(), "u_lightPos"),
                 1, glm::value_ptr(lightPos));

    // 2) dispatch compute
    constexpr GLuint groupSizeX = 8, groupSizeY = 8;
    const GLuint groupsX = (GLuint(width)  + groupSizeX - 1) / groupSizeX;
    const GLuint groupsY = (GLuint(height) + groupSizeY - 1) / groupSizeY;
    glDispatchCompute(groupsX, groupsY, 1);

    // 3) barrier so the texture writes are visible to the next pass
    glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);
}
