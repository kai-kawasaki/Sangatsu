//
// Created by kylez on 4/17/2025.
//

#include "Globals.h"
#include "InputManager.h"
#include "Camera.h"
#include <GLFW/glfw3.h>

static Camera* s_cam = nullptr;

void InputManager::init(GLFWwindow *window, Camera* cam) {
    s_cam = cam;
    glfwSetKeyCallback(window, key_callback);
    glfwSetCursorPosCallback(window, cursorCallback);
    glfwSetScrollCallback(window, scrollCallback);
    glfwSetMouseButtonCallback(window, mouse_button_callback);
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
    if (s_cam) {
        s_cam->processScroll(yoffset);
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
