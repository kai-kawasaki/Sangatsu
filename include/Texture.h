//
// Created by kylez on 4/17/2025.
//

#ifndef TEXTURE_H
#define TEXTURE_H

#pragma once
#include <glad/glad.h>
#include <string>
#include <vector>

class Texture {
public:
    Texture(const std::string &filePath);
    Texture(const std::vector<std::string> &filePaths);
    ~Texture();
    void bind(GLuint unit) const;
    GLuint id() const { return _textureID; }

private:
    GLuint _textureID = 0;
    int    _width = 0, _height = 0, _layers = 0;
};

// class Texture {
//     public:
//         explicit Texture(const std::string& filePath);
//         ~Texture();
//
//         void bind(GLuint unit=0) const;
//         [[nodiscard]] GLuint id() const;
//
//     private:
//         GLuint _textureID{};
// };

#endif //TEXTURE_H
