//
// Created by kylez on 4/17/2025.
//

#include "Shader.h"
#include "ShaderPreprocessor.h"
#include <iostream>
#include <cstdio>

Shader::Shader(const char* vertexPath, const char* fragmentPath) {
    auto vCode = ShaderPreprocessor::preprocessShader(vertexPath);
    auto fCode = ShaderPreprocessor::preprocessShader(fragmentPath);
    GLuint vs = compile(GL_VERTEX_SHADER,   vCode);
    GLuint fs = compile(GL_FRAGMENT_SHADER, fCode);

    _program = glCreateProgram();
    glAttachShader(_program, vs);
    glAttachShader(_program, fs);
    glLinkProgram(_program);

    int ok;
    glGetProgramiv(_program,GL_LINK_STATUS,&ok);
    if (!ok) {
        char buf[512];
        glGetProgramInfoLog(_program,512,nullptr,buf);
        std::fprintf(stderr,"ERROR::PROGRAM::LINK_FAILED\n%s\n",buf);
    }
    glDeleteShader(vs);
    glDeleteShader(fs);
}

Shader::~Shader() {
    glDeleteProgram(_program);
}

void Shader::use() const {
    glUseProgram(_program);
}

GLuint Shader::id() const {
    return _program;
}

GLuint Shader::compile(GLenum type, const std::string& source) {
    GLuint s = glCreateShader(type);
    const char* c = source.c_str();
    glShaderSource(s, 1, &c, nullptr);
    glCompileShader(s);
    int ok;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char buf[512];
        glGetShaderInfoLog(s, 512, nullptr, buf);
        const char* shaderType = (type == GL_VERTEX_SHADER) ? "VERTEX" :
                                 (type == GL_FRAGMENT_SHADER) ? "FRAGMENT" : "UNKNOWN";
        std::fprintf(stderr, "ERROR::SHADER::COMPILATION_FAILED\nType: %s\nSource:\n%s\nError Log:\n%s\n",
                     shaderType, source.c_str(), buf);
    }
    return s;
}