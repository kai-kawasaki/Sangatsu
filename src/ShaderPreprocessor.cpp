//
// Created by kylez on 4/17/2025.
//

#include "ShaderPreprocessor.h"
#include <fstream>
#include <sstream>
#include <iostream>
#include <filesystem>

std::string ShaderPreprocessor::_doPreprocess(const std::string& filePath, std::unordered_set<std::string>& includedFiles) {
    if (includedFiles.count(filePath)) {
        return "";
    }
    includedFiles.insert(filePath);

    std::ifstream in(filePath);
    if (!in.is_open()) {
        std::cerr << "Failed to open shader file: " << filePath << std::endl;
        return "";
    }

    std::stringstream out;
    std::string line;
    while (std::getline(in,line)) {
        if (line.rfind("#include",0)==0) {
            auto inc = line.substr(8);
            // trim quotes/whitespace...
            inc.erase(inc.find_last_not_of(" \"\t\r\n")+1);
            inc.erase(0,inc.find_first_not_of(" \"\t\r\n"));
            auto path = std::filesystem::path(filePath)
                          .parent_path()/inc;
            out<<_doPreprocess(path.string(), includedFiles);
        } else {
            out<<line<<"\n";
        }
    }

    return out.str();
}

std::string ShaderPreprocessor::preprocessShader(const std::string &filePath) {
    std::unordered_set<std::string> includedFiles;
    return _doPreprocess(filePath, includedFiles);
}
