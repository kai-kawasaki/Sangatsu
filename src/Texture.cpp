//
// Created by kylez on 4/17/2025.
//


#include "Texture.h"
#include <SOIL.h>
#include <iostream>

Texture::Texture(const std::string &filePath) {
    glGenTextures(1,&_textureID);
    glBindTexture(GL_TEXTURE_2D,_textureID);
    // wrap/filtering...
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);

    int w,h;
    unsigned char* img = SOIL_load_image(
        filePath.c_str(), &w, &h, nullptr, SOIL_LOAD_RGBA);
    if (img) {
        glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,w,h,0,
                     GL_RGBA,GL_UNSIGNED_BYTE,img);
        glGenerateMipmap(GL_TEXTURE_2D);
        SOIL_free_image_data(img);
    } else {
        std::cerr<<"Failed to load texture: "<<filePath<<"\n";
    }
    glBindTexture(GL_TEXTURE_2D,0);
}

Texture::~Texture() {
    glDeleteTextures(1,&_textureID);
}

void Texture::bind(GLuint unit) const {
    glActiveTexture(GL_TEXTURE0+unit);
    glBindTexture(GL_TEXTURE_2D,_textureID);
}

GLuint Texture::id() const {
    return _textureID;
}