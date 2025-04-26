//
// Created by kylez on 4/17/2025.
//

#ifndef INPUTMANAGER_H
#define INPUTMANAGER_H

#pragma once
#include <GLFW/glfw3.h>
#include "Camera.h"

class InputManager {
    public:
        static void init(GLFWwindow* window, Camera* cam, float* scrollOffset);
    private:
        static Camera* s_cam;
        static float* _scrollOffset;

        static void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods);
        static void cursorCallback(GLFWwindow* window, double xpos, double ypos);
        static void scrollCallback(GLFWwindow* window, double xoffset, double yoffset);
        static void mouse_button_callback(GLFWwindow* window, int button, int action, int mods);
        static void framebuffer_size_callback(GLFWwindow* window, int width, int height);
};

#endif //INPUTMANAGER_H
