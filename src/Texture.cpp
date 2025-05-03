//
// Created by kylez on 4/17/2025.
//


#include "Texture.h"
#include <SOIL.h>
#include <iostream>

#include "Texture.h"
#include <SOIL.h>
#include <iostream>

static void setupParameters(GLenum target) {
    // wrap/filtering...
    glTexParameteri(target, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(target, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(target, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
}

// Single-file ctor just delegates to array version:
Texture::Texture(const std::string &filePath)
: Texture(std::vector<std::string>{filePath})
{ }



// Array ctor
Texture::Texture(const std::vector<std::string> &filePaths) {
    if (filePaths.empty()) {
        std::cerr << "Texture array: no file paths provided\n";
        return;
    }

    _texturePaths = filePaths;

    bindPaths(filePaths);
}

Texture::Texture(const std::string &directory, bool recursive) {
    try {
        if (recursive) {
            for (const auto& entry : std::filesystem::recursive_directory_iterator(directory)) {
                if (entry.is_regular_file()) {
                    _texturePaths.push_back(entry.path().string());
                }
            }
        } else {
            for (const auto& entry : std::filesystem::directory_iterator(directory)) {
                if (entry.is_regular_file()) {
                    _texturePaths.push_back(entry.path().string());
                }
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

int Texture::getTextureID(const std::string& fileName) const {
    for (size_t i = 0; i < _texturePaths.size(); ++i) {
        if (_texturePaths[i].find(fileName) != std::string::npos) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

void Texture::bind(GLuint unit) const {
    glActiveTexture(GL_TEXTURE0 + unit);
    // if it's a single image, it's still in a 2D_ARRAY with 1 layer
    glBindTexture(GL_TEXTURE_2D_ARRAY, _textureID);
}

void Texture::bindPaths(const std::vector<std::string>& filePaths) {
    // First, load the first image to get dimensions
    int w, h, channels;
    unsigned char* firstImg = SOIL_load_image(
        filePaths[0].c_str(), &w, &h, &channels, SOIL_LOAD_RGBA);
    if (!firstImg) {
        std::cerr << "Failed to load texture: " << filePaths[0] << "\n";
        return;
    }
    SOIL_free_image_data(firstImg);

    _width  = w;
    _height = h;
    _layers = static_cast<int>(filePaths.size());

    // Create and bind the array texture
    glGenTextures(1, &_textureID);
    glBindTexture(GL_TEXTURE_2D_ARRAY, _textureID);
    setupParameters(GL_TEXTURE_2D_ARRAY);

    // Allocate immutable storage: one level, RGBA8, w×h×layers
    glTexStorage3D(GL_TEXTURE_2D_ARRAY,
                   1,                // mip-levels
                   GL_RGBA8,
                   _width,
                   _height,
                   _layers);

    // Now upload each layer
    for (int layer = 0; layer < _layers; ++layer) {
        int lw, lh, lc;
        unsigned char* data = SOIL_load_image(
            filePaths[layer].c_str(), &lw, &lh, &lc, SOIL_LOAD_RGBA);

        if (!data) {
            std::cerr << "Failed to load texture: " << filePaths[layer] << "\n";
            continue;
        }
        if (lw != _width || lh != _height) {
            std::cerr << "Warning: texture size mismatch in layer "
                      << layer << "\n";
        }

        // copy into layer
        glTexSubImage3D(GL_TEXTURE_2D_ARRAY,
                        0,                  // mip level
                        0, 0, layer,        // x,y,layer offset
                        lw, lh, 1,          // width,height,depth=1
                        GL_RGBA,
                        GL_UNSIGNED_BYTE,
                        data);

        SOIL_free_image_data(data);
    }

    glGenerateMipmap(GL_TEXTURE_2D_ARRAY);
    glBindTexture(GL_TEXTURE_2D_ARRAY, 0);
}

// Texture::Texture(const std::string &filePath) {
//     glGenTextures(1,&_textureID);
//     glBindTexture(GL_TEXTURE_2D,_textureID);
//     // wrap/filtering...
//     glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_REPEAT);
//     glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_REPEAT);
//     glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR_MIPMAP_LINEAR);
//     glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
//
//     int w,h;
//     unsigned char* img = SOIL_load_image(
//         filePath.c_str(), &w, &h, nullptr, SOIL_LOAD_RGBA);
//     if (img) {
//         glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,w,h,0,
//                      GL_RGBA,GL_UNSIGNED_BYTE,img);
//         glGenerateMipmap(GL_TEXTURE_2D);
//         SOIL_free_image_data(img);
//     } else {
//         std::cerr<<"Failed to load texture: "<<filePath<<"\n";
//     }
//     glBindTexture(GL_TEXTURE_2D,0);
// }
//
// Texture::~Texture() {
//     glDeleteTextures(1,&_textureID);
// }
//
// void Texture::bind(GLuint unit) const {
//     glActiveTexture(GL_TEXTURE0+unit);
//     glBindTexture(GL_TEXTURE_2D,_textureID);
// }
//
// GLuint Texture::id() const {
//     return _textureID;
// }