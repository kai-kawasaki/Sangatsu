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
#include <iostream>


Application::Application(int w, int h, const char* t) {
    // 1) Create window & make its context current
    _window = std::make_unique<Window>(w, h, t);

    // 2) Load GLAD
    if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) {
        std::cerr << "ERROR: Failed to initialize GLAD\n";
        std::exit(EXIT_FAILURE);
    }

//If you want to use OpenGL debug output, Upgrade OpenGL Version to 4.3
    // // 3) GL debug callback (optional)
    // if (glDebugMessageCallback) {
    //     glEnable(GL_DEBUG_OUTPUT);
    //     glDebugMessageCallback(
    //         [](GLenum, GLenum, GLuint, GLenum, GLsizei, const GLchar* msg, const void*) {
    //             std::cerr << "[GL DEBUG] " << msg << "\n";
    //         },
    //         nullptr
    //     );
    // } else {
    //     std::cerr << "[WARN] Debug callback not supported on this context\n";
    // }

    // 4) Camera & input (we still use InputManager for mouse/scroll)
    _camera = std::make_unique<Camera>();
    InputManager::init(_window->handle(), _camera.get());
    glfwSetInputMode(_window->handle(), GLFW_CURSOR, GLFW_CURSOR_DISABLED);

    // 5) Load shaders, textures, SSBO, ray‑marcher
    _shader = std::make_unique<Shader>(
        (std::string(SHADERS_DIR) + "/vertex.glsl").c_str(),
        (std::string(SHADERS_DIR) + "/fragment.glsl").c_str()
    );
    _texture = std::make_unique<Texture>(
        std::string(TEXTURES_DIR) + "/test.png"
    );

    _objects = {
        Object(3, -0.5, 5),
        Object(3, 10,5),
        Object(5, 5, 5),
        Object(6, 5, 5)
    };
    _ssbo       = std::make_unique<SSBOManager>(_objects);
    _rayMarcher = std::make_unique<RayMarcher>(*_shader);
    _rayMarcher->init();

    // 6) Initialize camera position & time
    _camPos    = glm::vec3(0.0f, 2.0f, -4.0f);
    _camera->setPosition(_camPos);
    _prevTime  = glfwGetTime();
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

        // Free‑look mode if Alt
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
            _texture->id()
        );

        glfwSwapBuffers(win);
        glfwPollEvents();
    }
}

void Application::cleanup() {
    // unique_ptrs clean up automatically
}
