
#define REFLECTIONS true
#define RAYBOUNCES 2
#define REFLECTIONSTRENGTH 0.2
#define REFLECTIONFALLOFF 0.5

// Add a helper function to reflect a ray around a normal
void reflectRay(inout vec3 rayD, in vec3 normal) {
    rayD = rayD + 2.0 * -dot(normal, rayD) * normal;
}