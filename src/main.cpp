#include "Application.h"
#include "Globals.h"

#ifdef _WIN32
    extern "C" {
        __declspec(dllexport) unsigned long NvOptimusEnablement = 0x00000001;
        __declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
    }
#endif


int main() {
    Application app(widthG,heightG,"Ray Marcher");
    app.run();
    return 0;
}
