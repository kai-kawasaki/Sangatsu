//
// Created by kylez on 4/17/2025.
//

#ifndef WINDOW_H
#define WINDOW_H

#pragma once
#include <GLFW/glfw3.h>

class Window {
    public:
        Window(int width, int height, const char* title);
        ~Window();

        // void makeContextCurrent();
        void swapBuffers() const;
        [[nodiscard]] bool shouldClose() const;
        static void pollEvents();
        // void setKeyCallback(GLFWkeyfun callback);
        // void setMousePositionCallback(GLFWcursorposfun callback);
        // void setScrollCallback(GLFWscrollfun callback);
        [[nodiscard]] GLFWwindow* handle() const;
    private:
        GLFWwindow* _win;
        static void error_callback(int error, const char* description);
};

#endif //WINDOW_H
