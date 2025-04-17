//
// Created by kylez on 4/17/2025.
//

#include "Window.h"

#include <cstdio>
#include <cstdlib>

Window::Window(int width, int height, const char* title) {
    glfwSetErrorCallback(error_callback);

    if (!glfwInit()) {
        std::exit(EXIT_FAILURE);
    }

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    _win = glfwCreateWindow(width, height, title, nullptr, nullptr);

    if (!_win) {
        glfwTerminate();
        std::exit(EXIT_FAILURE);
    }

    glfwMakeContextCurrent(_win);
}

Window::~Window() {
    glfwDestroyWindow(_win);
    glfwTerminate();
}

bool Window::shouldClose() const {
    return glfwWindowShouldClose(_win);
}

void Window::swapBuffers() const {
    glfwSwapBuffers(_win);
}

void Window::pollEvents() {
    glfwPollEvents();
}

GLFWwindow* Window::handle() const {
    return _win;
}

void Window::error_callback(int, const char* description) {
    fprintf(stderr, "Error: %s\n", description);
}
