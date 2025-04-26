#include "Application.h"
#include "Globals.h"

int main() {
    widthG = 1080;
    heightG = 720;
    Application app(widthG,heightG,"Ray Marcher");
    app.run();
    return 0;
}
