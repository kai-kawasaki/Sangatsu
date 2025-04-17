//
// Created by kylez on 4/17/2025.
//

#ifndef CAMERA_H
#define CAMERA_H

#pragma once
#include <glm/glm.hpp>

class Camera {
public:
    Camera();

    void processMouseMovement(double xpos, double ypos);
    void processScroll(double yoffset);

    [[nodiscard]] glm::vec3 position() const;
    [[nodiscard]] glm::vec3 target() const;

    void setPosition(const glm::vec3& p) { _position = p; }
    void setTarget  (const glm::vec3& t) { _target = t; }

    [[nodiscard]] glm::vec3 forward()   const { return _forward; }
    [[nodiscard]] glm::vec3 forwardXZ() const { return _forwardXZ; }
    [[nodiscard]] glm::vec3 right()     const { return _right; }

private:
    double _theta, _phi;
    float _sensitivity;
    float _radius;

    glm::vec3 _position, _target, _forward, _right, _forwardXZ;
    bool _firstMove;
    double _lastX, _lastY;
    void updateVectors();

};

#endif //CAMERA_H
