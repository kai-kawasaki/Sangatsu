set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
cmake_minimum_required(VERSION 3.14)
project(opengl-boilerplate LANGUAGES C CXX)

project(opengl-boilerplate LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(EXECUTABLE_OUTPUT_PATH ${PROJECT_BINARY_DIR}/bin)

# --- 1. Dependencies via FetchContent ---
include(FetchContent)

# GLFW
FetchContent_Declare(glfw
    GIT_REPOSITORY https://github.com/glfw/glfw.git
    GIT_TAG 3.3.8
    FIND_PACKAGE_ARGS # Try system first, then fetch
)
set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(GLFW_INSTALL OFF CACHE BOOL "" FORCE)

# GLM (Header only)
FetchContent_Declare(glm
    GIT_REPOSITORY https://github.com/g-truc/glm.git
    GIT_TAG 1.0.1
)

# FreeType
FetchContent_Declare(freetype
    GIT_REPOSITORY https://github.com/freetype/freetype.git
    GIT_TAG VER-2-12-1
)

# STB (Single-file header-only libraries)
FetchContent_Declare(stb
    GIT_REPOSITORY https://github.com/nothings/stb.git
    GIT_TAG master
)

FetchContent_MakeAvailable(glfw glm freetype stb)

# --- 2. OpenGL (Built-in) ---
find_package(OpenGL REQUIRED)

# --- 3. Executable & Sources ---
# Using file(GLOB) is usually discouraged, but for a boilerplate, 
# it's easier than listing 30 files manually.
file(GLOB_RECURSE SOURCES "src/*.cpp" "external/glad/src/glad.c")

add_executable(${PROJECT_NAME} ${SOURCES})

target_compile_definitions(${PROJECT_NAME} PRIVATE 
    SHADERS_DIR="${CMAKE_CURRENT_SOURCE_DIR}/shaders"
    TEXTURES_DIR="${CMAKE_CURRENT_SOURCE_DIR}/textures"
    GLFW_INCLUDE_NONE  # This also fixes your 'redefined' warning
)

# --- 4. Include Directories ---
target_include_directories(${PROJECT_NAME} PRIVATE 
    ${stb_SOURCE_DIR}
    include 
    src
    external/glad/include
)

# --- 5. Linking (The "Clean" Part) ---
target_link_libraries(${PROJECT_NAME} PRIVATE
    glfw
    freetype
    glm::glm
    OpenGL::GL
    ${CMAKE_DL_LIBS} # Required for GLAD on Linux
)

# Windows-specific tweaks
if(WIN32)
    # Prevents "cannot find -lopengl32" errors by using the alias
    target_link_libraries(${PROJECT_NAME} PRIVATE OpenGL::GL)
endif()