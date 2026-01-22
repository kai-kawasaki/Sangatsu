//
// Created by kylez on 1/22/2026.
//

#ifndef DEBUG_VISUALIZE_H
#define DEBUG_VISUALIZE_H

#pragma once
#include <vector>
#include <glm/glm.hpp>
#include <glad/glad.h>
#include "BVH.h"
#include "Shader.h"

enum class DebugVisualizationMode {
    NONE = 0,
    BVH_BOUNDS = 1,
    BVH_HEATMAP = 2,
    OBJECT_BOUNDS = 3,
    PERFORMANCE_OVERLAY = 4,
};

class DebugVisualize {
public:
    DebugVisualize();
    ~DebugVisualize();

    // Initialize with shaders
    void init(float screenWidth, float screenHeight);

    // Update visualization state
    void toggleMode();
    void setMode(DebugVisualizationMode mode);
    void cycleMode();
    DebugVisualizationMode currentMode() const { return _currentMode; }

    // Render visualizations
    void render(const BVHBuilder* bvh, const std::vector<Object>& objects,
                const glm::mat4& viewProj, float deltaTime);

    // Performance tracking (stub methods for future use)
    void recordRefitTime(float ms) { /* unused */ }
    void recordRebuildTime(float ms) { /* unused */ }
    void recordFrameTime(float ms) { /* unused */ }

    // Cleanup
    void cleanup();

private:
    DebugVisualizationMode _currentMode = DebugVisualizationMode::NONE;
    float _screenWidth = 1920.0f;
    float _screenHeight = 1080.0f;

    // VAO/VBO/EBO for wireframe cube
    GLuint _boxVAO = 0;
    GLuint _boxVBO = 0;
    GLuint _boxEBO = 0;
    GLsizei _boxIndexCount = 0;

    // Simple line shader program
    GLuint _program = 0;
    GLint _uViewProj = -1;
    GLint _uModel = -1;
    GLint _uColor = -1;

    // Performance metrics
    std::vector<float> _frameTimeSamples;
    static constexpr int FRAME_SAMPLE_COUNT = 60;

    // Helper methods
    void renderBVHBounds(const BVHBuilder* bvh, const glm::mat4& viewProj);
    void renderBVHHeatmap(const BVHBuilder* bvh, const std::vector<Object>& objects, const glm::mat4& viewProj);
    void renderObjectBounds(const std::vector<Object>& objects, const glm::mat4& viewProj);
    void renderPerformanceOverlay(float deltaTime);

    void createBoxGeometry();
    void createDebugProgram();
    void drawBox(const glm::vec3& min, const glm::vec3& max, const glm::vec4& color, const glm::mat4& viewProj);
    glm::vec4 getColorForDensity(float density);
};

#endif // DEBUG_VISUALIZE_H
