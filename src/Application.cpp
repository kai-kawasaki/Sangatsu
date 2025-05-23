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

#include <glad/gl.h>
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
#include <BVH.h>

// static constexpr float kMaxTraceDistance   = 100.0f;
// static constexpr float kHalfSize           = 0.865f;
// static constexpr float kRadius             = glm::sqrt(3.0f) * kHalfSize;

void logOpenGLInfo() {
    const GLubyte* vendor = glGetString(GL_VENDOR);
    const GLubyte* renderer = glGetString(GL_RENDERER);
    const GLubyte* version = glGetString(GL_VERSION);

    std::cout << "Vendor: " << vendor << std::endl;
    std::cout << "Renderer: " << renderer << std::endl;
    std::cout << "OpenGL Version: " << version << std::endl;
}

Application::Application(int w, int h, const char* t) {
    // 1) Create a window and make its context current
    _window = std::make_unique<Window>(w, h, t);

    // 2) Load GLAD
    if (!gladLoaderLoadGL()) {
        std::cerr << "ERROR: Failed to initialize GLAD\n";
        std::exit(EXIT_FAILURE);
    }

    // Log OpenGL information
    logOpenGLInfo();

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
        (std::string(SHADERS_DIR) + "/render.comp").c_str()
    );

    _texture = std::make_unique<Texture>(
        std::string(TEXTURES_DIR), true
    );
    _texture->bind(0);

    // initial voxel list
    _objects = {
        Object({4, 1, 3}, glm::vec3(0.5f), 10, {0, 1, 0}),
        // Object({4, 2, 5}, glm::vec3(0.5f), 1, 1, 2, 1, 0.5),
        // Object({0, 10, 0}, glm::vec3(0.5f), 10, {0, 1, 0}),
        Object({5, 5, 6}, glm::vec3(0.5f), 0, {0, 0, 1}/*, 1, 0.5, 1*/),
        Object({6, 5, 6}, glm::vec3(0.5f), 0, {1, 1, 0}/*, 1, 0.5, 0*/),
        Object({0, 0, 0}, {10,0.5,10}, 0, {0, 1, 0}),
        // Object({0, 0, 0}, {10,0.5,10}, 0, 1, "stylized-grass1", *_texture, 0.75f, 0.1f),
        // Object({7,7,7}, glm::vec3(0.5), 1, 1, "vertical-streak-cliff", *_texture, 0.25f, 0.01f),
        Object({5, 5, 1}, glm::vec3(1.0f), 11, {0.761, 0, 1}/*, 5, 0.3f, 1*/),
        Object({1, 1, 1}, glm::vec3(0.5f), 0, {0.7, 0, 1}/*, 5, 0.3f*/),
        Object({1, 3, 8}, glm::vec3(0.5f), 2, {0.7, 0.5, 1}/*, 5, 0.3f*/),
        Object({4, 1, 1}, glm::vec3(0.5f), 0, {1, 0, 1}/*, 5, 0.3f*/),
        Object({4, 1, 5}, glm::vec3(0.5f), 1, {0.5, 1, 1}/*, 5, 0.3f*/),
        Object({5, 4, 4}, glm::vec3(0.5f), 0, 1, "chiseled-cobble", *_texture, 0.75f, 0.3f/*, 1, 0.5, 1*/),
        Object({3, 4, 4}, glm::vec3(0.5f), 1, 1, "worn-shiny-metal", *_texture, 0.25f, 0.01f/*, 1, 0.5, 0*/),
    };

    BVHBuilder bvh;
    bvh.build(_objects, 1);

    for (int i = 0; i < bvh.nodes.size(); ++i) {
        const auto &n = bvh.nodes[i];
        std::cout
            << "Node " << i
            << " | bounds: [" << n.bounds.min.x << ", " << n.bounds.min.y << ", " << n.bounds.min.z
            << " to "        << n.bounds.max.x << ", " << n.bounds.max.y << ", " << n.bounds.max.z << "]"
            << " | left: "  << n.left
            << " | right: " << n.right
            << " | start: " << n.start
            << " | count: " << n.count;

        // if this is a leaf, print its object indices
        if (n.left < 0 && n.count > 0) {
            std::cout << " | objects:";
            for (int j = 0; j < n.count; ++j) {
                int objIdx = bvh.objectIndices[n.start + j];
                std::cout << " " << objIdx;
            }
        }
        std::cout << "\n";
    }

    _ssbo       = std::make_unique<SSBOManager>(_objects);
    _rayMarcher = std::make_unique<RayMarcher>(*_shader);
    _fbo = std::make_unique<FBOManager>(w, h);
    GLuint colorTex = _fbo->getColorTexture();
    glBindImageTexture(0, colorTex, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);
    // _fbo->bind();
    bvh.generateSSBO();

    // ——— Disable culling: render all objects ———
    // _visibleIndices.resize(_objects.size());
    // std::iota(_visibleIndices.begin(), _visibleIndices.end(), 0);
    // _ssbo->updateIndices(_visibleIndices, _frameIndex);

    _camPos   = glm::vec3(0.0f, 2.0f, -4.0f);
    _camera->setPosition(_camPos);
    _prevTime = glfwGetTime();
    glViewport(0, 0, w, h);
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

        // ——— CPU culling (distance + frustum) ———
        _frameIndex = (_frameIndex + 1) % FRAMES_IN_FLIGHT;
        _visibleIndices.clear();

        glm::vec3 camFwd   = _camera->forward();
        glm::vec3 camRight = _camera->right();
        glm::vec3 camUp    = _camera->up();

        float tanHFOV = std::tan(_camera->halfHFOV());
        float tanVFOV = std::tan(_camera->halfVFOV());

//         for (size_t i = 0; i < _objects.size(); i++) {
//             /* TODO: Reimplement culling with BVH.
//             const auto& obj = _objects[i];
//             glm::vec3 toObj = obj.position - _camPos;
//
//             // project onto camera axes
//             float zc = glm::dot(toObj, camFwd);
//             float xc = glm::dot(toObj, camRight);
//             float yc = glm::dot(toObj, camUp);
//
//             // distance cull, expanded by radius
//             if (zc + kRadius <= 0.0f || zc - kRadius > kMaxTraceDistance)
//                 continue;
//
//             // frustum planes cull, expanded by radius
//             float halfW = zc * tanHFOV;
//             float halfH = zc * tanVFOV;
//             if (xc >  halfW + kRadius || xc < -halfW - kRadius) continue;
//             if (yc >  halfH + kRadius || yc < -halfH - kRadius) continue;
//             */
//
//             _visibleIndices.push_back(i);
//         }
//
//         _ssbo->updateIndices(_visibleIndices, _frameIndex);

        // Calculate sun position with circular motion
        float sunRadius = 500.0f; // Distance from origin
        float angleRadians = static_cast<float>(cur * (2.0f * M_PI / 120.0f)); // Full rotation in 120 seconds
        glm::vec3 sunPosition = glm::vec3(
            sunRadius * std::cos(angleRadians),
            sunRadius * std::sin(angleRadians),
            0.0f
        );

        int windowW, windowH;
        glfwGetWindowSize(win, &windowW, &windowH);

        // 1) Query FBO size
        int fbW = _fbo->getWidth();
        int fbH = _fbo->getHeight();

        // 2) Dispatch the compute pass
        _rayMarcher->render(
            static_cast<float>(fbW),
            static_cast<float>(fbH),
            static_cast<float>(cur),
            _scrollOffset,
            _camera->position(),
            _camera->target(),
            flashlightOn,
            renderMode,
            0,              // textureID is now unused
            sunPosition,
            _visibleIndices.size()
        );

        // 3) Blit the compute-written texture to the screen
        glBindFramebuffer(GL_READ_FRAMEBUFFER, _fbo->getFBO());
        glReadBuffer(GL_COLOR_ATTACHMENT0);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
        glBlitFramebuffer(
            0, 0, fbW, fbH,
            0, 0, windowW, windowH,
            GL_COLOR_BUFFER_BIT,
            GL_NEAREST
        );
        glBindFramebuffer(GL_FRAMEBUFFER, 0);

        glfwSwapBuffers(win);
        glfwPollEvents();
    }
}

void Application::cleanup() {
    // unique_ptrs clean up automatically
}