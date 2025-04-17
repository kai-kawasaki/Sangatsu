//
// Created by kylez on 4/17/2025.
//

#ifndef TEXTURE_H
#define TEXTURE_H

#pragma once
#include <glad/glad.h>
#include <string>

class Texture {
    public:
        explicit Texture(const std::string& filePath);
        ~Texture();

        void bind(GLuint unit=0) const;
        [[nodiscard]] GLuint id() const;

    private:
        GLuint _textureID{};
};

#endif //TEXTURE_H
