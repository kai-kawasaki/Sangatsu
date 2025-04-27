#version 430 core
#include "hg_sdf.glsl"

in vec3 color;
layout (location = 0) out vec4 FragColor;

struct object {
    float x, y, z;
    float r, g, b;
};

// triPlanar(programTexture1, p, normal, size);

layout (std430, binding = 0) buffer VisibleObjects {
    object visibleObjects[];
};

layout (std430, binding = 1) buffer AllObjects {
    object allObjects[];
};


precision mediump float;

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_scroll;
uniform vec3 u_camPos;
uniform vec3 u_camTarget;
uniform int u_flashlight;
uniform int u_renderMode;
uniform int u_countBox;

uniform sampler2D programTexture1;

const float MAX_STEPS = 500.0;
const float MIN_DIST_TO_SDF = 0.001;
const float MAX_DIST_TO_TRAVEL = 100.0;
const float EPSILON = 0.001;
const float LOD_MULTIPLIER = 0.06;


struct Light {
  float size;
  vec3 pos;
  vec3 col;
  vec3 dir;
  float focus;
  float spread;
};

vec3 triPlanar(sampler2D tex, vec3 p, vec3 normal, float size) {
    p*=(1.0/size);
    normal = abs(normal);
    normal = pow(normal, vec3(5.0));
    normal /= normal.x + normal.y + normal.z;
    return (texture(tex, p.xy * 0.5 + 0.5) * normal.z +
    texture(tex, p.xz * 0.5 + 0.5) * normal.y +
    texture(tex, p.yz * 0.5 + 0.5) * normal.x).rgb;
}

vec2 minID(vec2 res1, vec2 res2) {
    return (res1.x < res2.x) ? res1 : res2;
}

vec2 calcSDF(vec3 pos, bool cull) {

//    vec2 plane = ;
//    vec2 dist = vec2(fPlane(pos, vec3(0.0, 1.0, 0.0), 1.0), -1.0);
    vec2 dist = vec2(MAX_DIST_TO_TRAVEL, -1.0);

    if (cull) {
        for (int i = 0; i < u_countBox; i++) {
            vec3 location = vec3(visibleObjects[i].x, visibleObjects[i].y, visibleObjects[i].z);
            dist = minID(vec2(fBox(pos-location, vec3(0.5)), float(i)), dist);
        }
    } else {
        for (int i = 0; i < allObjects.length(); i++) {
            vec3 location = vec3(allObjects[i].x, allObjects[i].y, allObjects[i].z);
            dist = minID(vec2(fBox(pos-location, vec3(0.5)), float(i)), dist);
        }
    }


    return dist;
}


float calcAO(vec3 pos, vec3 normal) { //Ambient occlusion
    float occ = 0.0;
    float sca = 1.0;

    for(int i=0; i<5; i++) {
        float hrconst = 0.03; // larger values = AO
        float hr = hrconst + 0.15*float(i)/4.0;
        vec3 aopos =  normal * hr + pos;
        float dd = calcSDF( aopos , true).x;
        occ += (hr-dd)*sca;
        sca *= 0.95;
    }
    return clamp(1.0 - occ*1.5, 0.0, 1.0);
}


// https://iquilezles.org/articles/rmshadows

float calcSoftshadow(in vec3 ro, in vec3 rd, float mint, float maxt, float w) {
    float res = 1.0;
    float ph = 1e20;
    float t = mint;
    for( int i=0; i<256 && t<maxt; i++ )
    {
        float h = calcSDF(ro + rd*t, false).x;
        if( h<0.001 )
            return 0.0;
        //float y = h*h/(2.0*ph);
        float y = (i==0) ? 0.0 : h*h/(2.0*ph);
        float d = sqrt(h*h-y*y);
        res = min( res, d/(w*max(0.0,t-y)) );
        ph = h;
        t += h;
    }
    return res;
}


vec4 getNormal(vec3 pos) {
    vec2 dist = calcSDF(pos, true);
    vec2 e = vec2(EPSILON, 0.0);

    vec3 normal = dist.x - vec3(
        calcSDF(pos-e.xyy, true).x,
        calcSDF(pos-e.yxy, true).x,
        calcSDF(pos-e.yyx, true).x);

    return vec4(normalize(normal), dist.y);
}


float rMarch(vec3 rOrig, vec3 rDir) {
    float dOrig = 0.0; // distance from ray origin

    for(int i=0; i<MAX_STEPS; i++) {
        vec3 rPos = rOrig + rDir * dOrig;
        float dSurf = calcSDF(rPos, true).x;
        dOrig += dSurf;
        if(dOrig > MAX_DIST_TO_TRAVEL || abs(dSurf) < MIN_DIST_TO_SDF*clamp(((dOrig*dOrig-3)*LOD_MULTIPLIER),1,MAX_DIST_TO_TRAVEL*MAX_DIST_TO_TRAVEL*LOD_MULTIPLIER)) break;
        //if(dOrig > MAX_DIST_TO_TRAVEL || abs(dSurf) < MIN_DIST_TO_SDF) break;
    }

    return dOrig;
}

vec3 getLight(vec3 p, vec3 rd, float id) {
    vec3 lightPos = vec3(200.0, 550.0, -250.0);
    vec3 L = normalize(lightPos - p);
    vec4 N = getNormal(p);
    vec3 V = -rd;
    vec3 R = reflect(-L, N.xyz);

    // Fetch the object's color based on its ID
    int objID = int(id);
    vec3 color = vec3(visibleObjects[objID].r, visibleObjects[objID].g, visibleObjects[objID].b);
//    vec3 color = vec3(objID/100.0f, 0, 0);


    vec3 specColor = vec3(0.6, 0.5, 0.4);
    vec3 specular = 1.3 * specColor * pow(clamp(dot(R, V), 0.0, 1.0), 10.0);
    vec3 diffuse = 0.9 * color * clamp(dot(L, N.xyz), 0.0, 1.0);
    vec3 ambient = 0.05 * color;
    vec3 fresnel = 0.15 * color * pow(1.0 + dot(rd, N.xyz), 3.0);

    // shadows
    float shadow = calcSoftshadow(p, L, 0.01, 100.0, 0.01);
    // occ
    float occ = calcAO(p,N.xyz);
    // back
    vec3 back = 0.05 * color * clamp(dot(N.xyz, -L), 0.0, 1.0);

    return  (back + ambient + fresnel) * occ + (specular * occ + diffuse) * shadow;
    //    return back;
}

vec3 getColor(vec3 rOrig, vec3 rDir) {
    vec3 col = vec3(0.0);
    vec3 background = vec3(0.01);

    float dist = rMarch(rOrig, rDir);

    if (dist<MAX_DIST_TO_TRAVEL) {
        vec3 pos = rOrig + rDir * dist; // surface point location
        vec4 normalVal = getNormal(pos);
        vec3 normal = normalVal.xyz; //surface normal
        vec3 rDirRef = reflect(rDir, normal); // reflected ray
        float matID = normalVal.w; // material ID

        col += getLight(pos, rDir, matID);
        //col = abs(normal);
    }
    else {
        col+=background;
    }
    return clamp(col, 0.0, 1.0);
}

// method that can generat uv coordinates with an offset for supersampling
vec2 getUV(vec2 offset) {
    return ((gl_FragCoord.xy + offset) - 0.5 * u_resolution.xy) / u_resolution.y;
}

// Camera system explained here:
// https://www.youtube.com/watch?v=PBxuVlp7nuM
// new camera module that is cleaner to call
vec3 rCam(vec2 offset) {
    vec2 uv = getUV(offset);
    vec3 rOrig = u_camPos;
    vec3 lookat = rOrig+u_camTarget;
    float zoom = max(0.5,(u_scroll*0.05)+0.5);
    vec3 forward = normalize(lookat-rOrig),
        right = normalize(cross(forward, vec3(0, 1., 0))),
        up = cross(right, forward),
        center = forward*zoom,
        intersection = center + uv.x*right + uv.y*up,
        dir = normalize(intersection);
    return dir;
}

mat2 rotMatrix(float a) {
    float s = sin(a), c = cos(a);
    return mat2(c, -s, s, c);
}

// can super sample at different levels to reduce aliasing
vec3 renderPixel(int mode)
{
    vec3 col = vec3(0.0);
    float bxy = int(gl_FragCoord.x + gl_FragCoord.y) & 1;
    float nbxy = 1. - bxy;
    switch (mode) {
        case 0:
            col = getColor(u_camPos, vec3(0.0));
            col = vec3(getUV(vec2(0.0)), 0.0);
            break;
        case 1:
            col = getColor(u_camPos, rCam(vec2(0.0)));
            break;
        case 2:
            col = (getColor(u_camPos, rCam(vec2(0.33 * nbxy, 0.))) + getColor(u_camPos, rCam(vec2(0.33 * bxy, 0.66))));
            col /= 2;
            break;
        case 3:
            col = (getColor(u_camPos, rCam(vec2(0.66 * nbxy, 0.))) +
                  getColor(u_camPos, rCam(vec2(0.66 * bxy, 0.66))) +
                  getColor(u_camPos, rCam(vec2(0.33, 0.33))));
            col /= 3;
            break;
        case 4:
            vec4 e = vec4(0.125, -0.125, 0.375, -0.375);
            col = getColor(u_camPos, rCam(e.xz));
            col += getColor(u_camPos, rCam(e.yw));
            col += getColor(u_camPos, rCam(e.wx));
            col += getColor(u_camPos, rCam(e.zy));
            col /= 4;
            break;
    }
    return col;
}

// seven‑segment masks for digits 0–9 (bits gfedcba)
const int DIGIT_MASK[10] = int[10](
0x3F, // 0 = 0b0111111
0x06, // 1 = 0b0000110
0x5B, // 2 = 0b1011011
0x4F, // 3 = 0b1001111
0x66, // 4 = 0b1100110
0x6D, // 5 = 0b1101101
0x7D, // 6 = 0b1111101
0x07, // 7 = 0b0000111
0x7F, // 8 = 0b1111111
0x6F  // 9 = 0b1101111
);

// test whether fragCoord‑relative uv lies inside segment `s`
bool isInSegment(int s, vec2 uv) {
    // — horizontal bars —
    if (s == 0) { // top bar  (bit‑0)
        return uv.y > 0.85 && uv.y < 0.95
        && uv.x > 0.1  && uv.x < 0.9;
    }
    if (s == 6) { // middle bar (bit‑6)
        return uv.y > 0.475 && uv.y < 0.525
        && uv.x > 0.1   && uv.x < 0.9;
    }
    if (s == 3) { // bottom bar (bit‑3)
        return uv.y > 0.05 && uv.y < 0.15
        && uv.x > 0.1  && uv.x < 0.9;
    }

    // — vertical bars (unchanged) —
    if (s == 5) return uv.x>0.05 && uv.x<0.15 && uv.y>0.55 && uv.y<0.9;  // top‑left (bit‑5)
    if (s == 4) return uv.x>0.05 && uv.x<0.15 && uv.y>0.1  && uv.y<0.45; // bot‑left (bit‑4)
    if (s == 1) return uv.x>0.85 && uv.x<0.95 && uv.y>0.55 && uv.y<0.9;  // top‑right(bit‑1)
    if (s == 2) return uv.x>0.85 && uv.x<0.95 && uv.y>0.1  && uv.y<0.45; // bot‑right(bit‑2)

    return false;
}



// draws one digit (0–9) into a corner rectangle
//   fragXY   = gl_FragCoord.xy
//   base     = bottom‑left corner of this digit
//   sz       = size in pixels (width,height)
//   inout col = the color buffer to write white segments into
void drawDigit(int digit, vec2 fragXY, vec2 base, vec2 sz, inout vec3 col) {
    vec2 uv = (fragXY - base) / sz;
    // only inside our digit‐rect?
    if (uv.x<0.0 || uv.x>1.0 || uv.y<0.0 || uv.y>1.0) return;
    int mask = DIGIT_MASK[digit];
    for (int s = 0; s < 7; ++s) {
        if (((mask >> s) & 1) != 0 && isInSegment(s, uv)) {
            col = vec3(1.0);  // paint this pixel white
            break;
        }
    }
}


void main() {
    vec2 uv = getUV(vec2(0.0));

    vec3 rOrig = u_camPos; // Works with WASD without old camera rotation

    vec3 col = renderPixel(u_renderMode);
    col = pow(col, vec3(1.0/2.2));  // gamma
    vec3 finalCol = col;

    // — compute digit IDs
    int count = u_countBox;
//    int count = visibleObjects.length();
    int d0 = count % 10;
    int d1 = (count / 10) % 10;
    int d2 = (count / 100) % 10;

    // — decide where on screen
    vec2 corner   = vec2(10.0, u_resolution.y - 40.0);
    vec2 digitSize = vec2(20.0, 30.0);

    // — draw each digit (drawDigit is a void helper)
    drawDigit(d2, gl_FragCoord.xy, corner + vec2( 0.0, 0.0), digitSize, finalCol);
    drawDigit(d1, gl_FragCoord.xy, corner + vec2(25.0, 0.0), digitSize, finalCol);
    drawDigit(d0, gl_FragCoord.xy, corner + vec2(50.0, 0.0), digitSize, finalCol);

    // — finally write to the frame
    FragColor = vec4(finalCol, 1.0);
}
