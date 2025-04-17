//
// Created by kylez on 4/17/2025.
//

#ifndef SHADERPREPROCESSOR_H
#define SHADERPREPROCESSOR_H

#pragma once
#include <string>
#include <unordered_set>

class ShaderPreprocessor {
public:
    static std::string preprocessShader(const std::string& filePath);
private:
    static std::string _doPreprocess(const std::string& filePath, std::unordered_set<std::string>& includedFiles);
};

#endif //SHADERPREPROCESSOR_H
