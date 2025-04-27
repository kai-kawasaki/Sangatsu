//
// Created by kylez on 4/17/2025.
//

#include "RayMarcher.h"
#include <glm/gtc/type_ptr.hpp>

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

void RayMarcher::render(float w,float h,
                        float time,float scroll,
                        const glm::vec3& camPos,
                        const glm::vec3& camTarget,
                        bool flashlightOn,
                        int renderMode,
                        GLuint texID,
                        int countBox)
{
    _shader.use();
    glUniform2f(glGetUniformLocation(_shader.id(),"u_resolution"), w, h);
    glUniform1f(glGetUniformLocation(_shader.id(),"u_time"), time);
    glUniform1f(glGetUniformLocation(_shader.id(),"u_scroll"), scroll);
    glUniform3fv(glGetUniformLocation(_shader.id(),"u_camPos"),
                 1, glm::value_ptr(camPos));
    glUniform3fv(glGetUniformLocation(_shader.id(),"u_camTarget"),
                 1, glm::value_ptr(camTarget));
    glUniform1i(glGetUniformLocation(_shader.id(),"u_flashlight"), flashlightOn);
    glUniform1i(glGetUniformLocation(_shader.id(),"u_renderMode"), renderMode);
    glUniform1i(glGetUniformLocation(_shader.id(),"u_countBox"), countBox);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texID);

    glBindVertexArray(_vao);
    glDrawArrays(GL_TRIANGLES,0,6);
    glBindVertexArray(0);
}
