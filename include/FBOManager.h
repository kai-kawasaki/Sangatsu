//
// Created by kylez on 5/8/2025.
//

#ifndef FBOMANAGER_H
#define FBOMANAGER_H

#pragma once
#include <glad/gl.h>
#include <vector>
#include <glm/glm.hpp>

class FBOManager {
public:
    FBOManager(int width, int height);
    ~FBOManager();
    void bind() const;
    void unbind() const;
    void resize(int width, int height);
    int getWidth() const { return _width; }
    int getHeight() const { return _height; }
    GLuint getFBO() const { return _fbo; }
private:
    GLuint _fbo = 0;
    GLuint _colorTex = 0;
    GLuint _depthTex = 0;
    int    _width;
    int    _height;
};


#endif //FBOMANAGER_H
