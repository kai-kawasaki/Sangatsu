//
// Created by kylez on 4/17/2025.
//

#ifndef APPLICATION_H
#define APPLICATION_H

#pragma once
#include <memory>
#include <vector>
#include "Object.h"
#include <glm/glm.hpp>

#include "Window.h"
#include "Shader.h"
#include "Texture.h"
#include "Camera.h"
#include "SSBOManager.h"
#include "RayMarcher.h"
#include <memory>
#include "FBOManager.h"

class Application {
public:
    Application(int w,int h,const char* title);
    void run();

private:
    // void init();
    void loop();
    void cleanup();
    bool isVisible(const glm::vec3 &objPos);

    std::unique_ptr<Window>      _window;
    std::unique_ptr<Shader>      _shader;
    std::unique_ptr<Texture>     _texture;
    std::unique_ptr<Camera>      _camera;
    std::unique_ptr<SSBOManager> _ssbo;
    std::unique_ptr<FBOManager> _fbo;
    std::unique_ptr<RayMarcher>  _rayMarcher;

    std::vector<Object> _objects;

    float  _scrollOffset = 0.f;
    bool   _flashlightOn = false;
    int    _renderMode   = 1;
    double _prevTime     = 0.0;

    //–– camera state (were previously global variables)
    glm::vec3 _camPos    = { 0.0f, 2.0f, -4.0f };
    glm::vec3 _camTarget = { 0.0f, 0.0f,  0.0f };

    glm::vec3 _forward = {0.0f, 0.0f, 1.0f};
    glm::vec3 _forwardXZ = {0.0f, 0.0f, 1.0f};
    glm::vec3 _right     = { 0.0f, 1.0f, 0.0f };
    glm::vec3 _up        = { 0.0f, 1.0f, 0.0f };

    bool    _camOriented = false;
    float   _sensitivity = 0.5f;
    int _frameIndex = 0;
};


#endif //APPLICATION_H
