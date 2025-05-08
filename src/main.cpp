#include "Application.h"
#include "Globals.h"

extern "C" {
    // NVIDIA Optimus will pick this up; AMD driver ignores it
    __declspec(dllexport) unsigned long NvOptimusEnablement = 0x00000001;
    // AMD PowerXpress will pick this up; NVIDIA driver ignores it
    __declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}


int main() {
    Application app(widthG,heightG,"Ray Marcher");
    app.run();
    return 0;
}
