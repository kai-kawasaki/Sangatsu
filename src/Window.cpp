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

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 4);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, GLFW_TRUE);


#if __APPLE__
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
#endif

    _win = glfwCreateWindow(width, height, title, nullptr, nullptr);

    if (!_win) {
        glfwTerminate();
        std::exit(EXIT_FAILURE);
    }

    glfwSetFramebufferSizeCallback(_win, framebuffer_size_callback);
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

void Window::framebuffer_size_callback(GLFWwindow* window, int width, int height) {
    // glViewport(0, 0, width, height);
    return;
}
