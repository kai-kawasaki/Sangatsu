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
#include <glm/gtc/matrix_transform.hpp>
#include <cmath>
#include <iostream>
#include <vector>
#include <execution>
#include <mutex>
#include <numeric>
#include <algorithm>
#include <thread>
#include <BVH.h>


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
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) { // This is GLAD 1.0 syntax
        std::cerr << "Failed to initialize GLAD" << std::endl;
        return;
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
        Object({5.5, 5, 6}, glm::vec3(0.5f), 1, {0, 0, 1}/*, 1, 0.5, 1*/),
        Object({6, 5, 6}, glm::vec3(0.5f), 0, {1, 1, 0}/*, 1, 0.5, 0*/),
        Object({0, 0, 0}, {10,0.5,10}, 0, {0, 1, 0}),
        // Object({0, 0, 0}, {10,0.5,10}, 0, 1, "Grass004_2K-PNG", *_texture, 0.125f, 0.1f),
        // Object({7,7,7}, glm::vec3(0.5), 1, 1, "vertical-streak-cliff", *_texture, 0.25f, 0.01f),
        // Object({5, 5, 1}, glm::vec3(1.0f), 11, 1, "red-plaid", *_texture, 4.0f, 0.01/*, 5, 0.3f, 1*/),
        Object({1, 1, 1}, glm::vec3(0.5f), 0, {0.7, 0, 1}/*, 5, 0.3f*/),
        Object({1, 3, 8}, glm::vec3(0.5f), 2, {1.0, 1.0, 1.0f}/*, 5, 0.3f*/),
        Object({4, 1, 1}, glm::vec3(0.5f), 0, {1, 0, 1}/*, 5, 0.3f*/),
        Object({4, 1, 5}, glm::vec3(0.5f), 1, {0.5, 1, 1}/*, 5, 0.3f*/),
        Object({5, 4, 4}, glm::vec3(0.5f), 0, 1, "chiseled-cobble", *_texture, 1.0f, 0.3f/*, 1, 0.5, 1*/),
        Object({3, 4, 4}, glm::vec3(0.5f), 1, 1, "worn-shiny-metal", *_texture, 3.0f, 0.1f/*, 1, 0.5, 0*/),
    };

    _bvh = std::make_unique<BVHBuilder>();
    _bvh->build(_objects, 1);
    _bvh->uploadInitial();

    _debugViz = std::make_unique<DebugVisualize>();
    _debugViz->init(static_cast<float>(w), static_cast<float>(h));

    _ssbo       = std::make_unique<SSBOManager>(_objects);
    _rayMarcher = std::make_unique<RayMarcher>(*_shader);
    _fbo = std::make_unique<FBOManager>(w, h);
    GLuint colorTex = _fbo->getColorTexture();
    glBindImageTexture(0, colorTex, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA32F);

    _camPos   = glm::vec3(0.0f, 2.0f, -4.0f);
    _camera->setPosition(_camPos);
    _prevTime = glfwGetTime();
    glViewport(0, 0, w, h);



    // In your initialization code
    GLuint reflectionCache;
    glGenTextures(1, &reflectionCache);
    glBindTexture(GL_TEXTURE_2D, reflectionCache);

    // Use half resolution for the cache to save memory
    int cacheWidth = widthG;
    int cacheHeight = heightG;

    // Use RGBA16F for higher precision
    glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA16F, cacheWidth, cacheHeight);

    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    // Bind as image for compute shader access
    glBindImageTexture(1, reflectionCache, 0, GL_FALSE, 0, GL_READ_WRITE, GL_RGBA16F);

    GLuint shadowCache;
    glGenTextures(1, &shadowCache);
    glBindTexture(GL_TEXTURE_2D, shadowCache);

    glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA16F, cacheWidth, cacheHeight);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glBindImageTexture(2, shadowCache, 0, GL_FALSE, 0, GL_READ_WRITE, GL_RGBA16F);
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

        // Debug visualization controls
        static bool prevVKey = false;
        bool currentVKey = glfwGetKey(win, GLFW_KEY_V) == GLFW_PRESS;
        if (currentVKey && !prevVKey) {
            _debugViz->cycleMode();
        }
        prevVKey = currentVKey;

        _frameIndex = (_frameIndex + 1) % FRAMES_IN_FLIGHT;

        // Demo: animate object 1 (sphere) bouncing
        {
            float bounceY = 5.0f + 2.0f * std::sin(static_cast<float>(cur) * 2.0f);
            _objects[1].position.y = bounceY;
            markObjectDirty(1);
        }

        // BVH dynamic updates
        if (!_dirtyObjects.empty()) {
            _bvh->rebuildIfNeeded(_objects, _dirtyObjects, _rebuildThreshold, 1);
            _bvh->refit(_objects, _dirtyObjects, _refitBudget, true);
            _bvh->updateGPU();
            _bvh->bindBuffers();
            _ssbo->syncAllObjects(_objects);
            // Validate BVH (optional debug)
            // if (!_bvh->validate(_objects, false)) {
            //     std::cerr << "BVH validation failed after refit!\n";
            // }
            _dirtyObjects.clear();
        }

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
            sunPosition,
            _objects.size()
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

        // 4) Render debug visualizations
        if (_debugViz) {
            const float zoom = _camera->zoom();
            // Match ray marcher camera: half-FOV = atan(1 / zoom)
            const float fov = 2.0f * std::atan(1.0f / zoom);
            glm::mat4 projection = glm::perspective(
                fov,
                static_cast<float>(fbW) / static_cast<float>(fbH),
                0.1f,
                1000.0f
            );
            glm::mat4 view = _camera->getViewMatrix();
            glm::mat4 viewProj = projection * view;

            _debugViz->render(_bvh.get(), _objects, viewProj, static_cast<float>(dt));
        }

        glfwSwapBuffers(win);
        glfwPollEvents();
    }
}

void Application::cleanup() {
    if (_bvh) _bvh->cleanup();
    if (_debugViz) _debugViz->cleanup();
    // unique_ptrs clean up automatically
}
void Application::markObjectDirty(const int objIndex) {
    if (objIndex < 0 || objIndex >= static_cast<int>(_objects.size())) return;
    _dirtyObjects.push_back(objIndex);
}

void Application::markAllObjectsDirty() {
    _dirtyObjects.clear();
    for (int i = 0; i < static_cast<int>(_objects.size()); ++i) {
        _dirtyObjects.push_back(i);
    }
}
