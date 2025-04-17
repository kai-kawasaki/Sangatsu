//
// Created by kylez on 4/17/2025.
//

#include "Utilities.h"

float clampf(float value, float min, float max) {
    if (value < min) {
        return min;
    }
    if (value > max) {
        return max;
    }
    return value;
}