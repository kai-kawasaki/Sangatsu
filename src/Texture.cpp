//
// Created by kylez on 4/17/2025.
//

#include "Texture.h"
#include <glad/glad.h>
#include <iostream>
#include <filesystem>

// This must be defined in exactly one .cpp file
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

static void setupParameters(GLenum target) {
    glTexParameteri(target, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(target, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(target, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
}

// Single-file ctor
Texture::Texture(const std::string &filePath)
    : Texture(std::vector<std::string>{filePath})
{ }

// Array ctor
Texture::Texture(const std::vector<std::string> &filePaths) {
    if (filePaths.empty()) {
        std::cerr << "Texture array: no file paths provided\n";
        return;
    }
    bindPaths(filePaths);
}

// Directory ctor
Texture::Texture(const std::string &directory, bool recursive) {
    try {
        if (recursive) {
            for (const auto& entry : std::filesystem::recursive_directory_iterator(directory)) {
                if (entry.is_regular_file()) _texturePaths.push_back(entry.path().string());
            }
        } else {
            for (const auto& entry : std::filesystem::directory_iterator(directory)) {
                if (entry.is_regular_file()) _texturePaths.push_back(entry.path().string());
            }
        }
    } catch (const std::filesystem::filesystem_error& e) {
        std::cerr << "Error accessing directory: " << e.what() << '\n';
    }

    if (_texturePaths.empty()) {
        std::cerr << "Texture array: no file paths found in directory\n";
        return;
    }

    bindPaths(_texturePaths);
}

Texture::~Texture() {
    if (_textureID) {
        glDeleteTextures(1, &_textureID);
    }
}

void Texture::bindPaths(const std::vector<std::string>& filePaths) {
    // OpenGL expects (0,0) at the bottom-left, but images are top-left.
    stbi_set_flip_vertically_on_load(true);

    // 1. Load the first image to determine array dimensions
    int w, h, channels;
    unsigned char* firstImg = stbi_load(filePaths[0].c_str(), &w, &h, &channels, 4); // Force RGBA
    if (!firstImg) {
        std::cerr << "Failed to load reference texture: " << filePaths[0] 
                  << " | Reason: " << stbi_failure_reason() << "\n";
        return;
    }

    _width  = w;
    _height = h;
    _layers = static_cast<int>(filePaths.size());

    glGenTextures(1, &_textureID);
    glBindTexture(GL_TEXTURE_2D_ARRAY, _textureID);
    setupParameters(GL_TEXTURE_2D_ARRAY);

    // 2. Allocate immutable storage
    // Using 4 levels for mipmaps (you can calculate this properly if needed)
    glTexStorage3D(GL_TEXTURE_2D_ARRAY, 4, GL_RGBA8, _width, _height, _layers);

    // Upload first image before freeing
    glTexSubImage3D(GL_TEXTURE_2D_ARRAY, 0, 0, 0, 0, _width, _height, 1, GL_RGBA, GL_UNSIGNED_BYTE, firstImg);
    stbi_image_free(firstImg);

    // 3. Upload subsequent layers
    for (int layer = 1; layer < _layers; ++layer) {
        int lw, lh, lc;
        unsigned char* data = stbi_load(filePaths[layer].c_str(), &lw, &lh, &lc, 4);

        if (!data) {
            std::cerr << "Failed to load layer " << layer << ": " << filePaths[layer] << "\n";
            continue;
        }

        if (lw != _width || lh != _height) {
            std::cerr << "Warning: texture size mismatch in layer " << layer 
                      << " (" << filePaths[layer] << ")\n";
        }

        glTexSubImage3D(GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer, lw, lh, 1, GL_RGBA, GL_UNSIGNED_BYTE, data);
        stbi_image_free(data);
    }

    glGenerateMipmap(GL_TEXTURE_2D_ARRAY);
    glBindTexture(GL_TEXTURE_2D_ARRAY, 0);

    _texturePaths = filePaths;
}

void Texture::bind(GLuint unit) const {
    glActiveTexture(GL_TEXTURE0 + unit);
    glBindTexture(GL_TEXTURE_2D_ARRAY, _textureID);
}

int Texture::getTextureID(const std::string& fileName) const {
    for (size_t i = 0; i < _texturePaths.size(); ++i) {
        if (_texturePaths[i].find(fileName) != std::string::npos) {
            return static_cast<int>(i);
        }
    }
    return -1;
}