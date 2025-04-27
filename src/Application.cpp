// src/Application.cpp
// Created by kylez on 4/17/2025.

#include "Application.h"
#include "Globals.h"
#include "Window.h"
#include "Shader.h"
#include "Texture.h"
#include "Camera.h"
#include "InputManager.h"
#include "SSBOManager.h"
#include "RayMarcher.h"

#include <glad/glad.h>
#include <GLFW/glfw3.h>
#include <glm/glm.hpp>
#include <glm/gtc/constants.hpp>
#include <cmath>
#include <iostream>
#include <vector>
#include <execution>
#include <mutex>
#include <numeric>
#include <algorithm>
#include <thread>

static constexpr float kMaxTraceDistance   = 100.0f;
static constexpr float kHalfSize           = 0.865f;
static constexpr float kRadius             = glm::sqrt(3.0f) * kHalfSize;
// static constexpr float kCullAngleMarginDeg = 2.0f;
// static constexpr float kCullAngleMargin   = glm::radians(kCullAngleMarginDeg);

Application::Application(int w, int h, const char* t) {
    // 1) Create window & make its context current
    _window = std::make_unique<Window>(w, h, t);

    // 2) Load GLAD
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
        std::cerr << "ERROR: Failed to initialize GLAD\n";
        std::exit(EXIT_FAILURE);
    }

    glEnable(GL_DEBUG_OUTPUT);
    glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);

    glDebugMessageControl(
        GL_DONT_CARE,             // source
        GL_DONT_CARE,             // type
        GL_DEBUG_SEVERITY_NOTIFICATION, // severity to disable
        0, nullptr,
        GL_FALSE
    );


    glDebugMessageCallback(
      [](GLenum source,
         GLenum type,
         GLuint id,
         GLenum severity,
         GLsizei length,
         const GLchar* msg,
         const void*)
      {
        std::cerr
          << "[GL ERROR] "
          << msg
          << " (source=" << source
          << ", type="   << type
          << ", id="     << id
          << ", sev="    << severity
          << ")\n";
      },
      nullptr
    );


    // 4) Camera & input
    _camera = std::make_unique<Camera>();
    InputManager::init(_window->handle(), _camera.get(), &_scrollOffset);
    glfwSetInputMode(_window->handle(), GLFW_CURSOR, GLFW_CURSOR_DISABLED);

    // 5) Load shaders, textures, SSBO, ray-marcher
    _shader = std::make_unique<Shader>(
        (std::string(SHADERS_DIR) + "/vertex.glsl").c_str(),
        (std::string(SHADERS_DIR) + "/fragment.glsl").c_str()
    );
    _texture = std::make_unique<Texture>(
        std::string(TEXTURES_DIR) + "/test.png"
    );

    // initial voxel list
    _objects = {
        Object({4, 1, 3}, {1, 0, 0}),
        Object({0, 10, 0}, {0, 1, 0}),
        Object({5, 5, 6}, {0, 0, 1}),
        Object({6, 5, 5}, {1, 1, 0}),
    };
    for (int i = -8; i < 8; i++) {
        for (int j = -8; j < 8; j++) {
            _objects.emplace_back(Object({i, 0, j}, {1, 1, 1}));
        }
    }

    _ssbo       = std::make_unique<SSBOManager>(_objects);
    _rayMarcher = std::make_unique<RayMarcher>(*_shader);
    _rayMarcher->init();

    // ——— Disable culling: render all objects ———
    _visibleIndices.resize(_objects.size());
    std::iota(_visibleIndices.begin(), _visibleIndices.end(), 0);
    _ssbo->updateIndices(_visibleIndices, _frameIndex);

    // 6) Initialize camera position & time
    _camPos   = glm::vec3(0.0f, 2.0f, -4.0f);
    _camera->setPosition(_camPos);
    _prevTime = glfwGetTime();
}

void Application::run() {
    loop();
    cleanup();
}

void Application::loop() {
    GLFWwindow* win = _window->handle();
    while (!glfwWindowShouldClose(win)) {
        double cur = glfwGetTime();
        float  dt  = static_cast<float>(cur - _prevTime);
        _prevTime  = cur;

        // Frame setup
        int w, h;
        glfwGetFramebufferSize(win, &w, &h);
        glViewport(0, 0, w, h);
        glClear(GL_COLOR_BUFFER_BIT);

        // ——— Movement based on glfwGetKey ———
        float moveSpeed = 5.0f;
        float movement  = moveSpeed * dt;

        // Sprint if Shift
        if (glfwGetKey(win, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS)
            movement *= 2.0f;

        // Free-look mode if Alt
        _camOriented = (glfwGetKey(win, GLFW_KEY_LEFT_ALT) == GLFW_PRESS);
        if (_camOriented)
            movement /= 5.0f;

        // Fetch camera axes
        glm::vec3 forward   = _camera->forward();
        glm::vec3 forwardXZ = glm::normalize(glm::vec3(forward.x, 0.0f, forward.z));
        glm::vec3 right     = _camera->right();

        if (_camOriented) {
            if (glfwGetKey(win, GLFW_KEY_W) == GLFW_PRESS)
                _camPos += movement * forward;
            if (glfwGetKey(win, GLFW_KEY_S) == GLFW_PRESS)
                _camPos -= movement * forward;
            if (glfwGetKey(win, GLFW_KEY_A) == GLFW_PRESS)
                _camPos -= movement * right;
            if (glfwGetKey(win, GLFW_KEY_D) == GLFW_PRESS)
                _camPos += movement * right;
        } else {
            if (glfwGetKey(win, GLFW_KEY_W) == GLFW_PRESS) {
                _camPos.x += movement * forwardXZ.x;
                _camPos.z += movement * forwardXZ.z;
            }
            if (glfwGetKey(win, GLFW_KEY_S) == GLFW_PRESS) {
                _camPos.x -= movement * forwardXZ.x;
                _camPos.z -= movement * forwardXZ.z;
            }
            if (glfwGetKey(win, GLFW_KEY_A) == GLFW_PRESS)
                _camPos -= movement * right;
            if (glfwGetKey(win, GLFW_KEY_D) == GLFW_PRESS)
                _camPos += movement * right;
        }

        // Vertical motion
        if (glfwGetKey(win, GLFW_KEY_SPACE) == GLFW_PRESS)
            _camPos.y += movement;
        if (glfwGetKey(win, GLFW_KEY_LEFT_CONTROL) == GLFW_PRESS)
            _camPos.y -= movement;

        // Update camera
        _camera->setPosition(_camPos);

        // // compute once per frame
        // // const float tanHFOV = std::tan(_camera->halfHFOV());
        // // const float tanVFOV = std::tan(_camera->halfVFOV());
        // float halfHFOVm = _camera->halfHFOV() + kCullAngleMargin;
        // float halfVFOVm = _camera->halfVFOV() + kCullAngleMargin;
        // const float tanHFOVm = std::tan(halfHFOVm);
        // const float tanVFOVm = std::tan(halfVFOVm);
        //
        // // ——— Parallel CPU culling into index list ———
        // _visibleIndices.clear();
        // const std::size_t objCount = _objects.size();
        // std::mutex idxMutex;
        //
        // // Build index list 0..objCount-1
        // std::vector<std::size_t> allIdx(objCount);
        // std::iota(allIdx.begin(), allIdx.end(), 0);
        //
        // auto cullTask = [&](std::size_t i) {
        //     const Object& obj = _objects[i];
        //     glm::vec3 toObj = glm::vec3(obj.x, obj.y, obj.z) - _camPos;
        //
        //     float zc = glm::dot(toObj, _camera->forward());
        //     if (zc + kRadius <= 0.0f || zc - kRadius > kMaxTraceDistance) return;
        //
        //     float xc = glm::dot(toObj, _camera->right());
        //     float yc = glm::dot(toObj, _camera->up());
        //     float halfW = zc * tanHFOVm;
        //     float halfH = zc * tanVFOVm;
        //     if (xc >  halfW + kRadius || xc < -halfW - kRadius) return;
        //     if (yc >  halfH + kRadius || yc < -halfH - kRadius) return;
        //
        //     std::lock_guard<std::mutex> lock(idxMutex);
        //     _visibleIndices.push_back(i);
        // };
        //
        // // Run culling in parallel over real iterators
        // std::for_each(
        //     std::execution::par,
        //     allIdx.begin(),
        //     allIdx.end(),
        //     cullTask
        // );
        //
        // // Update SSBO with only the visible subset
        // _ssbo->updateIndices(_visibleIndices);

        // ——— CPU culling (distance + frustum) ———
        _frameIndex = (_frameIndex + 1) % FRAMES_IN_FLIGHT;
        _visibleIndices.clear();

        glm::vec3 camFwd   = _camera->forward();
        glm::vec3 camRight = _camera->right();
        glm::vec3 camUp    = _camera->up();

        // // assume all cubes are size = 1.0; half‐edge = 0.5
        // static constexpr float kHalfSize = 0.865f;
        // // bounding‐sphere radius = half‑diagonal = √3 * halfEdge
        // static constexpr float kRadius   = glm::sqrt(3.0f) * kHalfSize;

        float tanHFOV = std::tan(_camera->halfHFOV());
        float tanVFOV = std::tan(_camera->halfVFOV());

        struct DepthIdx { float depth; size_t idx; };
        std::vector<DepthIdx> tmp;

        for (size_t i = 0; i < _objects.size(); i++) {
            const auto& obj = _objects[i];
            glm::vec3 toObj = obj.position - _camPos;

            // project onto camera axes
            float zc = glm::dot(toObj, camFwd);
            float xc = glm::dot(toObj, camRight);
            float yc = glm::dot(toObj, camUp);

            // 1) distance cull, expanded by radius
            if (zc + kRadius <= 0.0f || zc - kRadius > kMaxTraceDistance)
                continue;

            // 2) compute half‐angles once per frame
            // (you already have halfHFOV, halfVFOV from before)

            // 3) frustum planes cull, expanded by radius
            float halfW = zc * tanHFOV;
            float halfH = zc * tanVFOV;
            if (xc >  halfW + kRadius || xc < -halfW - kRadius) continue;
            if (yc >  halfH + kRadius || yc < -halfH - kRadius) continue;

            // _visibleIndices.push_back(i);
            tmp.push_back({ zc, i });
        }

        std::sort(tmp.begin(), tmp.end(), [](auto& a, auto& b) {return a.depth < b.depth;});

        _visibleIndices.resize(tmp.size());
        for (size_t i = 0; i < tmp.size(); i++) {
            _visibleIndices[i] = tmp[i].idx;
        }

        _ssbo->updateIndices(_visibleIndices, _frameIndex);



        // ——— Render ———
        _rayMarcher->render(
            static_cast<float>(w),
            static_cast<float>(h),
            static_cast<float>(cur),
            _scrollOffset,
            _camera->position(),
            _camera->target(),
            flashlightOn,
            renderMode,
            _texture->id(),
            _visibleIndices.size()
        );

        glfwSwapBuffers(win);
        glfwPollEvents();
    }
}

void Application::cleanup() {
    // unique_ptrs clean up automatically
}

void Application::setScrollOffset(float offset) {
    _scrollOffset = offset;

}