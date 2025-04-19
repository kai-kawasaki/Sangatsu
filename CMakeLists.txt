cmake_minimum_required(VERSION 3.10)
project(opengl-mingw-boilerplate)

# Add static linking for GCC runtime libraries
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -static-libgcc -static-libstdc++ -static")

set(EXECUTABLE_OUTPUT_PATH ${PROJECT_BINARY_DIR}/bin)

# Source and external package files
set(SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src")
set(EXT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/external")
aux_source_directory(${SRC_DIR} SOURCES)
set(GLFW_DIR "${EXT_DIR}/glfw")
set(GLAD_DIR "${EXT_DIR}/glad")
set(GLM_DIR "${EXT_DIR}/glm")
set(SOIL_DIR "${EXT_DIR}/soil")
set(FREETYPE_DIR "${EXT_DIR}/freetype")
link_directories(${GLFW_DIR}/lib ${SOIL_DIR}/lib ${FREETYPE_DIR}/lib)
include_directories(${PROJECT_SOURCE_DIR}/include)

# Add the executable
add_executable(${PROJECT_NAME} ${SOURCES}
        include/Application.h
        include/Window.h
        include/InputManager.h
        include/ShaderPreprocessor.h
        include/Shader.h
        include/Texture.h
        include/Camera.h
        include/SSBOManager.h
        include/Object.h
        include/Vertex.h
        include/RayMarcher.h
        include/Utilities.h
        src/Application.cpp
        src/Window.cpp
        src/InputManager.cpp
        src/ShaderPreprocessor.cpp
        src/Shader.cpp
        src/Texture.cpp
        src/Camera.cpp
        src/SSBOManager.cpp
        src/Object.cpp
        src/RayMarcher.cpp
        src/Utilities.cpp
        include/Globals.h
        src/Globals.cpp)
target_include_directories(${PROJECT_NAME} PRIVATE "${SRC_DIR}")
set_property(TARGET ${PROJECT_NAME} PROPERTY CXX_STANDARD 17)

target_compile_definitions(${PROJECT_NAME} PRIVATE
        SHADERS_DIR="${CMAKE_SOURCE_DIR}/shaders"
        TEXTURES_DIR="${CMAKE_SOURCE_DIR}/textures"
)

# Libraries
# GLFW
target_link_libraries(${PROJECT_NAME} glfw3)
target_include_directories(${PROJECT_NAME} PRIVATE "${GLFW_DIR}/include")
target_compile_definitions(${PROJECT_NAME} PRIVATE "GLFW_INCLUDE_NONE")

# GLAD
add_library("glad" "${GLAD_DIR}/src/glad.c")
target_include_directories("glad" PRIVATE "${GLAD_DIR}/include")
target_include_directories(${PROJECT_NAME} PRIVATE "${GLAD_DIR}/include")
target_link_libraries(${PROJECT_NAME} "glad" "${CMAKE_DL_LIBS}")

# GLM
target_include_directories(${PROJECT_NAME} PRIVATE "${GLM_DIR}")

# SOIL
target_link_libraries(${PROJECT_NAME} SOIL)
target_link_libraries(${PROJECT_NAME} opengl32)
target_include_directories(${PROJECT_NAME} PRIVATE "${SOIL_DIR}/include")

# Freetype
target_link_libraries(${PROJECT_NAME} freetype)
target_include_directories(${PROJECT_NAME} PRIVATE "${FREETYPE_DIR}/include")

# Portable Executable
# Define the output directory for the portable app
set(PORTABLE_OUTPUT_DIR ${PROJECT_BINARY_DIR}/PortableApp)

# Custom target to package the project
add_custom_target(Package ALL
        COMMAND ${CMAKE_COMMAND} -E remove_directory ${PORTABLE_OUTPUT_DIR}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${PORTABLE_OUTPUT_DIR}

        # Copy the executable
        COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:${PROJECT_NAME}> ${PORTABLE_OUTPUT_DIR}

        # Copy resource directories
        COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/shaders ${PORTABLE_OUTPUT_DIR}/shaders
        COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/textures ${PORTABLE_OUTPUT_DIR}/textures
)