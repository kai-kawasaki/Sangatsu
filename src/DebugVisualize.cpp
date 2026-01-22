//
// Created by kylez on 1/22/2026.
//

#include "DebugVisualize.h"
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <iostream>
#include <sstream>
#include <iomanip>
#include <algorithm>

DebugVisualize::DebugVisualize() = default;

DebugVisualize::~DebugVisualize() {
    cleanup();
}

void DebugVisualize::init(const float screenWidth, const float screenHeight) {
    _screenWidth = screenWidth;
    _screenHeight = screenHeight;

    // Create simple wireframe box geometry
    createBoxGeometry();
    createDebugProgram();
}

void DebugVisualize::createBoxGeometry() {
    if (_boxVAO != 0) return;

    // Define cube vertices
    float vertices[] = {
        // Front face
        -1, -1,  1,   1, -1,  1,   1,  1,  1,   -1,  1,  1,
        // Back face
        -1, -1, -1,  -1,  1, -1,   1,  1, -1,   1, -1, -1,
        // Top face
        -1,  1, -1,  -1,  1,  1,   1,  1,  1,   1,  1, -1,
        // Bottom face
        -1, -1, -1,   1, -1, -1,   1, -1,  1,  -1, -1,  1,
        // Right face
         1, -1, -1,   1,  1, -1,   1,  1,  1,   1, -1,  1,
        // Left face
        -1, -1, -1,  -1, -1,  1,  -1,  1,  1,  -1,  1, -1,
    };

    // Define box edges as line indices
    unsigned int indices[] = {
        0, 1,  1, 2,  2, 3,  3, 0,  // Front
        4, 5,  5, 6,  6, 7,  7, 4,  // Back
        8, 9,  9, 10, 10, 11, 11, 8, // Top
        12, 13, 13, 14, 14, 15, 15, 12, // Bottom
        16, 17, 17, 18, 18, 19, 19, 16, // Right
        20, 21, 21, 22, 22, 23, 23, 20, // Left
    };

    _boxIndexCount = static_cast<GLsizei>(sizeof(indices) / sizeof(indices[0]));

    glGenVertexArrays(1, &_boxVAO);
    glGenBuffers(1, &_boxVBO);
    glGenBuffers(1, &_boxEBO);

    glBindVertexArray(_boxVAO);

    glBindBuffer(GL_ARRAY_BUFFER, _boxVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _boxEBO);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW);

    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(float), nullptr);

    glBindVertexArray(0);
}

void DebugVisualize::createDebugProgram() {
    if (_program != 0) return;

    const char* vertSrc = R"(
        #version 430 core
        layout(location = 0) in vec3 aPos;
        uniform mat4 uViewProj;
        uniform mat4 uModel;
        void main() {
            gl_Position = uViewProj * uModel * vec4(aPos, 1.0);
        }
    )";

    const char* fragSrc = R"(
        #version 430 core
        layout(location = 0) out vec4 FragColor;
        uniform vec4 uColor;
        void main() {
            FragColor = uColor;
        }
    )";

    auto compileShader = [](GLenum type, const char* src) -> GLuint {
        GLuint shader = glCreateShader(type);
        glShaderSource(shader, 1, &src, nullptr);
        glCompileShader(shader);
        GLint ok = 0;
        glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
        if (!ok) {
            char log[512];
            glGetShaderInfoLog(shader, 512, nullptr, log);
            std::cerr << "Debug shader compile failed:\n" << log << "\n";
        }
        return shader;
    };

    GLuint vs = compileShader(GL_VERTEX_SHADER, vertSrc);
    GLuint fs = compileShader(GL_FRAGMENT_SHADER, fragSrc);

    _program = glCreateProgram();
    glAttachShader(_program, vs);
    glAttachShader(_program, fs);
    glLinkProgram(_program);
    GLint linked = 0;
    glGetProgramiv(_program, GL_LINK_STATUS, &linked);
    if (!linked) {
        char log[512];
        glGetProgramInfoLog(_program, 512, nullptr, log);
        std::cerr << "Debug program link failed:\n" << log << "\n";
    }
    glDeleteShader(vs);
    glDeleteShader(fs);

    _uViewProj = glGetUniformLocation(_program, "uViewProj");
    _uModel = glGetUniformLocation(_program, "uModel");
    _uColor = glGetUniformLocation(_program, "uColor");
}

void DebugVisualize::toggleMode() {
    if (_currentMode == DebugVisualizationMode::NONE) {
        _currentMode = DebugVisualizationMode::BVH_BOUNDS;
    } else {
        _currentMode = DebugVisualizationMode::NONE;
    }
}

void DebugVisualize::setMode(const DebugVisualizationMode mode) {
    _currentMode = mode;
}

void DebugVisualize::cycleMode() {
    int nextMode = (static_cast<int>(_currentMode) + 1) % 5;
    _currentMode = static_cast<DebugVisualizationMode>(nextMode);
}

void DebugVisualize::render(const BVHBuilder* bvh, const std::vector<Object>& objects,
                            const glm::mat4& viewProj, const float deltaTime) {
    if (_currentMode == DebugVisualizationMode::NONE) return;

    // Basic wireframe rendering setup
    glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    glDisable(GL_CULL_FACE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    switch (_currentMode) {
        case DebugVisualizationMode::BVH_BOUNDS:
            renderBVHBounds(bvh, viewProj);
            break;
        case DebugVisualizationMode::BVH_HEATMAP:
            renderBVHHeatmap(bvh, objects, viewProj);
            break;
        case DebugVisualizationMode::OBJECT_BOUNDS:
            renderObjectBounds(objects, viewProj);
            break;
        case DebugVisualizationMode::PERFORMANCE_OVERLAY:
            renderPerformanceOverlay(deltaTime);
            break;
        default:
            break;
    }

    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    glEnable(GL_CULL_FACE);
    glDisable(GL_BLEND);
}

void DebugVisualize::renderBVHBounds(const BVHBuilder* bvh, const glm::mat4& viewProj) {
    if (!bvh || bvh->nodes.empty() || _program == 0) return;

    for (const auto& node : bvh->nodes) {
        const glm::vec3 color = (node.left < 0)
                                    ? glm::vec3(0.0f, 1.0f, 0.0f)   // Leaf
                                    : glm::vec3(0.2f, 0.5f, 1.0f); // Internal
        drawBox(node.bounds.min, node.bounds.max, glm::vec4(color, 0.7f), viewProj);
    }
}

void DebugVisualize::renderBVHHeatmap(const BVHBuilder* bvh, const std::vector<Object>& objects, const glm::mat4& viewProj) {
    if (!bvh || bvh->nodes.empty() || _program == 0) return;

    // Simple density proxy based on leaf index; could be replaced with real counts if available
    for (size_t i = 0; i < bvh->nodes.size(); ++i) {
        const auto& node = bvh->nodes[i];
        if (node.left >= 0) continue; // internal
        float density = static_cast<float>(i % 10) / 10.0f;
        glm::vec4 color = getColorForDensity(density);
        drawBox(node.bounds.min, node.bounds.max, color, viewProj);
    }
}

void DebugVisualize::renderObjectBounds(const std::vector<Object>& objects, const glm::mat4& viewProj) {
    if (_program == 0) return;
    for (const auto& obj : objects) {
        glm::vec4 color(1.0f, 0.0f, 0.0f, 0.5f);
        const glm::vec3 min = obj.position - glm::vec3(obj.scale);
        const glm::vec3 max = obj.position + glm::vec3(obj.scale);
        drawBox(min, max, color, viewProj);
    }
}

void DebugVisualize::renderPerformanceOverlay(float deltaTime) {
    if (_frameTimeSamples.size() < FRAME_SAMPLE_COUNT) {
        _frameTimeSamples.push_back(deltaTime * 1000.0f);
    } else if (!_frameTimeSamples.empty()) {
        _frameTimeSamples[0] = deltaTime * 1000.0f;
        std::rotate(_frameTimeSamples.begin(), _frameTimeSamples.begin() + 1, _frameTimeSamples.end());
    }

    if (_frameTimeSamples.empty()) return;

    float avgFrameTime = 0.0f;
    for (float t : _frameTimeSamples) avgFrameTime += t;
    avgFrameTime /= static_cast<float>(_frameTimeSamples.size());
    float fps = 1000.0f / std::max(avgFrameTime, 0.001f);

    std::cout << "FPS: " << fps << " | Frame: " << avgFrameTime << "ms\n";
}

void DebugVisualize::drawBox(const glm::vec3& min, const glm::vec3& max, const glm::vec4& color, const glm::mat4& viewProj) {
    if (_program == 0 || _boxVAO == 0) return;

    const glm::vec3 center = (min + max) * 0.5f;
    const glm::vec3 extent = (max - min) * 0.5f;

    glm::mat4 model = glm::translate(glm::mat4(1.0f), center);
    model = glm::scale(model, extent);

    glUseProgram(_program);
    glUniformMatrix4fv(_uViewProj, 1, GL_FALSE, glm::value_ptr(viewProj));
    glUniformMatrix4fv(_uModel, 1, GL_FALSE, glm::value_ptr(model));
    glUniform4fv(_uColor, 1, glm::value_ptr(color));

    glBindVertexArray(_boxVAO);
    glDrawElements(GL_LINES, _boxIndexCount, GL_UNSIGNED_INT, nullptr);
    glBindVertexArray(0);
}

glm::vec4 DebugVisualize::getColorForDensity(float density) {
    density = glm::clamp(density, 0.0f, 1.0f);
    if (density < 0.25f) {
        float t = density / 0.25f;
        return glm::vec4(0.0f, t, 1.0f, 0.6f);
    } else if (density < 0.5f) {
        float t = (density - 0.25f) / 0.25f;
        return glm::vec4(0.0f, 1.0f, 1.0f - t, 0.6f);
    } else if (density < 0.75f) {
        float t = (density - 0.5f) / 0.25f;
        return glm::vec4(t, 1.0f, 0.0f, 0.6f);
    } else {
        return glm::vec4(1.0f, 1.0f - (density - 0.75f) / 0.25f, 0.0f, 0.6f);
    }
}

void DebugVisualize::cleanup() {
    if (_boxVAO != 0) {
        glDeleteVertexArrays(1, &_boxVAO);
        _boxVAO = 0;
    }
    if (_boxVBO != 0) {
        glDeleteBuffers(1, &_boxVBO);
        _boxVBO = 0;
    }
    if (_boxEBO != 0) {
        glDeleteBuffers(1, &_boxEBO);
        _boxEBO = 0;
    }
    if (_program != 0) {
        glDeleteProgram(_program);
        _program = 0;
    }
}
