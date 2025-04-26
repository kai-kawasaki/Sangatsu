//
// Created by kylez on 4/17/2025.
//

#include "Globals.h"
#include "InputManager.h"

#include <Utilities.h>
#include <glad/glad.h>

#include "Camera.h"
#include <GLFW/glfw3.h>

Camera* InputManager::s_cam = nullptr;
float* InputManager::_scrollOffset = nullptr;

void InputManager::init(GLFWwindow *window, Camera* cam, float* scrollOffset) {
    s_cam = cam;
    _scrollOffset = scrollOffset;
    glfwSetKeyCallback(window, key_callback);
    glfwSetCursorPosCallback(window, cursorCallback);
    glfwSetScrollCallback(window, scrollCallback);
    glfwSetMouseButtonCallback(window, mouse_button_callback);
    glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
}

void InputManager::key_callback(GLFWwindow *window,
                                int key,
                                int scancode,
                                int action,
                                int mods)
{
    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) {
        glfwSetWindowShouldClose(window, GLFW_TRUE);
        return;
    }

    if (action == GLFW_PRESS) {
        switch (key) {
            case GLFW_KEY_F:
                flashlightOn = !flashlightOn;      // toggle flashlight
                break;
            case GLFW_KEY_1:
                renderMode = 1;
                break;
            case GLFW_KEY_2:
                renderMode = 2;
                break;
            case GLFW_KEY_3:
                renderMode = 3;
                break;
            case GLFW_KEY_4:
                renderMode = 4;
                break;
            case GLFW_KEY_0:
                renderMode = 0;
                break;
            default:
                break;
        }
    }
}

void InputManager::cursorCallback(GLFWwindow *window,
                                  double xpos,
                                  double ypos)
{
    if (s_cam) {
        s_cam->processMouseMovement(xpos, ypos);
    }
}

void InputManager::scrollCallback(GLFWwindow *window,
                                  double xoffset,
                                  double yoffset)
{
    if (_scrollOffset) {
        *_scrollOffset = clampf(*_scrollOffset + static_cast<float>(yoffset), 0.1f, 500.f);
    }

    if (s_cam) {
        s_cam->processScroll(*_scrollOffset);
    }
}

void InputManager::mouse_button_callback(GLFWwindow *window,
                                         int button,
                                         int action,
                                         int mods)
{
    if (button == GLFW_MOUSE_BUTTON_LEFT && action == GLFW_PRESS) {
        // e.g. in the future you might cast a ray or start dragging
    }

    if (button == GLFW_MOUSE_BUTTON_RIGHT && action == GLFW_PRESS) {
        // e.g. in the future you might open a context menu
    }
}

void InputManager::framebuffer_size_callback(GLFWwindow *window, int width, int height) {
    glViewport(0, 0, width, height);
}

