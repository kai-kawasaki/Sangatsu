//
// Created by kylez on 4/17/2025.
//

#include "Camera.h"
#include "Utilities.h"
#include <cmath>
#include <glm/gtc/matrix_transform.hpp>
#include "Globals.h"

Camera::Camera() : _theta(45.0*PI/180.0),
                   _phi(30.0*PI/180.0),
                   _sensitivity(0.5f),
                   _radius(100.0f),
                   _firstMove(true),
                   _lastX(0.0),
                   _lastY(0.0),
                   _zoom(0.5f),
                   _halfVFOV(std::atan(1)),
                   _aspect(widthG/heightG),
                   _halfHFOV(std::atan((_aspect * 0.5f) / _zoom))
{
    updateVectors();
}

void Camera::processMouseMovement(double xpos, double ypos) {
    if (_firstMove) {
        _lastX = xpos; _lastY = ypos;
        _firstMove = false;
    }
    double dx = xpos - _lastX;
    double dy = ypos - _lastY;
    _lastX = xpos; _lastY = ypos;

    _theta += dy * _sensitivity * PI/180.0;
    _phi   += dx * _sensitivity * PI/180.0;
    // clamp
    const double eps=0.01;
    if (_theta < eps)         _theta = eps;
    if (_theta > PI - eps)    _theta = PI - eps;
    updateVectors();
}

void Camera::processScroll(float scrollOffset) {
    _radius = scrollOffset;
    _zoom = std::max(0.5f, scrollOffset * 0.05f + 0.5f);
    _halfVFOV = std::atan(0.5f / _zoom);
    updateVectors();
}

void Camera::processResize(int width, int height) {
    widthG = width;
    heightG = height;
    _aspect = float(width) / float(height);
    _halfHFOV = std::atan((_aspect * 0.5f) / _zoom);
}

void Camera::updateVectors() {
    _forward = {
        float(sin(_theta)*cos(_phi)),
        float(cos(_theta)),
        float(sin(_theta)*sin(_phi))
    };
    _forwardXZ = glm::normalize(glm::vec3(_forward.x, 0.0f, _forward.z));
    _right = glm::normalize(glm::cross(_forward,{0,1,0}));
    _up = glm::normalize(glm::cross(_right, _forward));
    _position = _radius * glm::vec3{
        float(sin(_theta)*cos(_phi)),
        float(cos(_theta)),
        float(sin(_theta)*sin(_phi))
    };
    _target = glm::normalize(_position);
}

glm::vec3 Camera::position()    const { return _position;    }
glm::vec3 Camera::target() const { return _target; }
glm::mat4 Camera::getViewMatrix() const {
    return glm::lookAt(_position, _position + _forward, _up);
}
