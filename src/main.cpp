#define GLAD_GL_IMPLEMENTATION
#include <glad/glad.h>
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>

#include <stdlib.h>
#include <stddef.h>
#include <stdio.h>
#include <fstream>
#include <sstream>
#include <iostream>
#include <unordered_set>
#include <filesystem>

#define M_PI 3.14159265358979323846

typedef struct Vertex
{
    glm::vec3 pos;
    glm::vec3 col;
} Vertex;

// Define vertices for two triangles that make up a rectangle covering the entire window
static const Vertex vertices[6] =
{
    { { -1.0f, -1.0f, 0.0f }, { 1.f, 0.f, 0.f } }, // Bottom-left
    { {  1.0f, -1.0f, 0.0f }, { 0.f, 1.f, 0.f } }, // Bottom-right
    { {  1.0f,  1.0f, 0.0f }, { 0.f, 0.f, 1.f } }, // Top-right

    { { -1.0f, -1.0f, 0.0f }, { 1.f, 0.f, 0.f } }, // Bottom-left
    { {  1.0f,  1.0f, 0.0f }, { 0.f, 0.f, 1.f } }, // Top-right
    { { -1.0f,  1.0f, 0.0f }, { 1.f, 1.f, 0.f } }  // Top-left
};

std::string preprocessShader(const std::string& filePath, std::unordered_set<std::string>& includedFiles) {
    if (includedFiles.find(filePath) != includedFiles.end()) {
        return ""; // Prevent recursive includes
    }
    includedFiles.insert(filePath);

    std::ifstream shaderFile(filePath);
    if (!shaderFile.is_open()) {
        std::cerr << "Failed to open shader file: " << filePath << std::endl;
        return "";
    }

    std::stringstream shaderStream;
    std::string line;
    while (std::getline(shaderFile, line)) {
        if (line.find("#include") == 0) {
            std::string includePath = line.substr(9);
            includePath.erase(includePath.find_last_not_of(" \"\t\n\r") + 1);
            includePath.erase(0, includePath.find_first_not_of(" \"\t\n\r"));
            std::filesystem::path includeFilePath = std::filesystem::path(filePath).parent_path() / includePath;
            shaderStream << preprocessShader(includeFilePath.string(), includedFiles);
        } else {
            shaderStream << line << "\n";
        }
    }

    return shaderStream.str();
}

std::string preprocessShader(const std::string& filePath) {
    std::unordered_set<std::string> includedFiles;
    return preprocessShader(filePath, includedFiles);
}

GLuint compileShader(GLenum type, const std::string& source) {
    GLuint shader = glCreateShader(type);
    const char* sourceCStr = source.c_str();
    glShaderSource(shader, 1, &sourceCStr, nullptr);
    glCompileShader(shader);

    int success;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) {
        char infoLog[512];
        glGetShaderInfoLog(shader, 512, nullptr, infoLog);
        fprintf(stderr, "ERROR::SHADER::COMPILATION_FAILED\n%s\n", infoLog);
    }

    return shader;
}

GLuint createShaderProgram(const char* vertexPath, const char* fragmentPath) {
    std::string vertexCode = preprocessShader(vertexPath);
    std::string fragmentCode = preprocessShader(fragmentPath);

    GLuint vertexShader = compileShader(GL_VERTEX_SHADER, vertexCode);
    GLuint fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragmentCode);

    GLuint shaderProgram = glCreateProgram();
    glAttachShader(shaderProgram, vertexShader);
    glAttachShader(shaderProgram, fragmentShader);
    glLinkProgram(shaderProgram);

    int success;
    glGetProgramiv(shaderProgram, GL_LINK_STATUS, &success);
    if (!success) {
        char infoLog[512];
        glGetProgramInfoLog(shaderProgram, 512, nullptr, infoLog);
        fprintf(stderr, "ERROR::PROGRAM::LINKING_FAILED\n%s\n", infoLog);
    }

    glDeleteShader(vertexShader);
    glDeleteShader(fragmentShader);

    return shaderProgram;
}

void error_callback(int error, const char* description)
{
    fprintf(stderr, "Error: %s\n", description);
}

float camPosX = 0.0f;
float camPosY = 2.0f;
float camPosZ = -4.0f;

glm::vec3 camTarget(0.0f, 0.0f, 0.0f);

double prevMouseX = 0.0, prevMouseY = 0.0;
double dx = 0.0, dy = 0.0;

// Camera orientation variables
float yaw = 0.0f; // Yaw is initialized to -90.0 degrees to look along the negative Z-axis
float pitch = 0.0f;
float sensitivity = 0.01f; // Mouse sensitivity
int renderMode = 1; // Placeholder for render mode
bool flashlightOn = false; // Placeholder for flashlight state

float clamp(float value, float min, float max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

void calc_camdir(float dx, float dy) {
    dx *= sensitivity;
    dy *= sensitivity;

    yaw -= dx; // Yaw controls horizontal rotation
    pitch = clamp(pitch - dy, -M_PI, M_PI); // Pitch controls vertical direction

    // Turn the pitch and yaw value into a normalized direction vector
    camTarget.x = std::sin(yaw);
    camTarget.y = pitch;
    camTarget.z = std::cos(yaw);
    camTarget = glm::normalize(camTarget);
}

void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
    if (action == GLFW_PRESS)
    {
      switch (key) {
        case GLFW_KEY_ESCAPE:
          glfwSetWindowShouldClose(window, GLFW_TRUE);
          break;
        case GLFW_KEY_F:
          flashlightOn = !flashlightOn; // Toggle flashlight state
          break;
        case GLFW_KEY_1:
          renderMode = 1; // Set render mode 1
          break;
        case GLFW_KEY_2:
          renderMode = 2; // Set render mode 2
          break;
        case GLFW_KEY_3:
          renderMode = 3; // Set render mode 3
          break;
        case GLFW_KEY_4:
          renderMode = 4; // Set render mode 4
          break;
        case GLFW_KEY_0:
          renderMode = 0; // Set render mode 0
          break;
        default:
          break;
      }
    }
}

void mouse_position_callback(GLFWwindow* window, double xpos, double ypos) {
    // Calculate the change in mouse position
    dx = xpos - prevMouseX;
    dy = ypos - prevMouseY; // Reversed since y-coordinates range from bottom to top

    // Update the previous mouse position
    prevMouseX = xpos;
    prevMouseY = ypos;

    // Update camera direction
    calc_camdir(dx, dy);

    std::cout << "Yaw: " << yaw << ", Pitch: " << pitch << "\n";
}

double scrollOffset = 0.0f;

void scroll_callback(GLFWwindow* window, double xoffset, double yoffset) {
    scrollOffset = (scrollOffset + yoffset >= 0.0) ? scrollOffset + yoffset : 0.0;
}

double previousTime = 0.0;

int main(void)
{
    GLFWwindow* window;
    GLuint vertex_array, vertex_buffer, program;
    GLint vpos_location, vcol_location;
    GLint resolutionLoc, timeLoc, scrollLoc, camPosLoc, camTargetLoc, flashlightLoc, renderModeLoc;

    glfwSetErrorCallback(error_callback);
    if (!glfwInit())
        exit(EXIT_FAILURE);

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    window = glfwCreateWindow(1080, 720, "Sangatsu", NULL, NULL);
    if (!window)
    {
        glfwTerminate();
        exit(EXIT_FAILURE);
    }

    glfwMakeContextCurrent(window);

    glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
    glfwSetCursorPosCallback(window, mouse_position_callback);
  
    gladLoadGLLoader((GLADloadproc)glfwGetProcAddress);
    glfwSwapInterval(1);

    glfwSetKeyCallback(window, key_callback);

    glfwSetScrollCallback(window, scroll_callback);

    glGenVertexArrays(1, &vertex_array);
    glBindVertexArray(vertex_array);

    glGenBuffers(1, &vertex_buffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

    program = createShaderProgram("../../shaders/vertex.glsl", "../../shaders/fragment.glsl");

    glUseProgram(program);

    vpos_location = glGetAttribLocation(program, "in_position");
    vcol_location = glGetAttribLocation(program, "vCol");

    // Get uniform locations for fragment shader
    resolutionLoc = glGetUniformLocation(program, "u_resolution");
    timeLoc = glGetUniformLocation(program, "u_time");
    scrollLoc = glGetUniformLocation(program, "u_scroll");
    camPosLoc = glGetUniformLocation(program, "u_camPos");
    camTargetLoc = glGetUniformLocation(program, "u_camTarget");
    flashlightLoc = glGetUniformLocation(program, "u_flashlight");
    renderModeLoc = glGetUniformLocation(program, "u_renderMode");

    glEnableVertexAttribArray(vpos_location);
    glVertexAttribPointer(vpos_location, 3, GL_FLOAT, GL_FALSE,
                          sizeof(Vertex), (void*)offsetof(Vertex, pos));
    glEnableVertexAttribArray(vcol_location);
    glVertexAttribPointer(vcol_location, 3, GL_FLOAT, GL_FALSE,
                          sizeof(Vertex), (void*)offsetof(Vertex, col));

    previousTime = glfwGetTime();

    int width, height;
    glfwGetWindowSize(window, &width, &height);
    glfwSetCursorPos(window, width / 2, height / 2);
    prevMouseX = width / 2;
    prevMouseY = height / 2;

    while (!glfwWindowShouldClose(window))
    {
        double currentTime = glfwGetTime();
        float deltaTime = static_cast<float>(currentTime - previousTime);
        previousTime = currentTime;

        float moveSpeed = 5.0f;
        float movement = moveSpeed * deltaTime;


        glfwGetFramebufferSize(window, &width, &height);
        glViewport(0, 0, width, height);
        glClear(GL_COLOR_BUFFER_BIT);

        // Check key states and update camera position
        if (glfwGetKey(window, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS)
        {
            movement *= 2.0f;
        }
        if (glfwGetKey(window, GLFW_KEY_W) == GLFW_PRESS)
        {
            camPosX += movement * sin(yaw);
            camPosZ += movement * cos(yaw);
        }
        if (glfwGetKey(window, GLFW_KEY_S) == GLFW_PRESS)
        {
            camPosX -= movement * sin(yaw);
            camPosZ -= movement * cos(yaw);
        }
        if (glfwGetKey(window, GLFW_KEY_A) == GLFW_PRESS)
        {
            camPosX += movement * cos(yaw);
            camPosZ -= movement * sin(yaw);
        }
        if (glfwGetKey(window, GLFW_KEY_D) == GLFW_PRESS)
        {
            camPosX -= movement * cos(yaw);
            camPosZ += movement * sin(yaw);
        }
        if (glfwGetKey(window, GLFW_KEY_LEFT_CONTROL) == GLFW_PRESS)
        {
            camPosY -= movement;
        }
        if (glfwGetKey(window, GLFW_KEY_SPACE) == GLFW_PRESS)
        {
            camPosY += movement;
        }

        // Set uniform values (placeholders)
        glUniform2f(resolutionLoc, (float)width, (float)height);
        glUniform1f(timeLoc, currentTime);
        glUniform1f(scrollLoc, scrollOffset);
        glUniform3f(camPosLoc, camPosX, camPosY, camPosZ);
        glUniform3f(camTargetLoc, camTarget.x, camTarget.y, camTarget.z);
        glUniform1i(flashlightLoc, flashlightOn);
        glUniform1i(renderModeLoc, renderMode);

        glDrawArrays(GL_TRIANGLES, 0, 6);

        // Center the mouse cursor
        glfwSetCursorPos(window, width / 2, height / 2);
        prevMouseX = width / 2;
        prevMouseY = height / 2;

        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    glDeleteBuffers(1, &vertex_buffer);
    glDeleteVertexArrays(1, &vertex_array);

    glfwDestroyWindow(window);
    glfwTerminate();
    exit(EXIT_SUCCESS);
}