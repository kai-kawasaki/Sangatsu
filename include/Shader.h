//
// Created by kylez on 4/17/2025.
//

#ifndef SHADER_H
#define SHADER_H

#pragma once
#include <glad/glad.h>
#include <string>

class Shader {
    public:
        Shader(const char* computePath);
        ~Shader();

        void use() const;
        [[nodiscard]] GLuint id() const;
    private:
        GLuint _program;
        static GLuint compile(GLenum type, const std::string& source);
};

#endif //SHADER_H
