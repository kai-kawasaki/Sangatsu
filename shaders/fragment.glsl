#version 430 core
#include "hg_sdf.glsl"

in vec3 color;
layout (location = 0) out vec4 FragColor;

struct object {
    float x;
    float y;
    float z;
};

layout (std430, binding = 0) buffer boxes {
    object box_positions[];
};


precision mediump float;

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_scroll;
uniform vec3 u_camPos;
uniform vec3 u_camTarget;
uniform int u_flashlight;
uniform int u_renderMode;

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

vec3 getMaterial(vec3 p, float id, vec3 normal, float size) {
    vec3 m;
    switch (int(id)) {
            case 1:
                m = vec3(1.0, 0.0, 0.0);
                break;
            case 2:
                m = triPlanar(programTexture1, p, normal, size);
                break;
            case 3:
                m = vec3(0.0, 0.0, 1.0);
                break;
            case 4:
                m = vec3(1.0, 1.0, 0.0);
                break;
            case 5:
                m = vec3(1.0, 0.0, 1.0);
                break;
            case 6:
                m = vec3(0.0, 1.0, 1.0);
                break;
            case 7:
                m = vec3(1.0, 1.0, 1.0);
                break;
            default:
                m = vec3(1.0);
                break;
    }
    return m;
}

vec2 calcSDF(vec3 pos) {

//    vec2 plane = ;
    vec2 dist = vec2(fPlane(pos, vec3(0.0, 1.0, 0.0), 1.0), 7.0);

    for (int i = 0; i < box_positions.length(); i++) {
        vec3 location = vec3(box_positions[i].x, box_positions[i].y, box_positions[i].z);
        dist = minID(vec2(fBox(pos-location, vec3(0.5)),2.0), dist);
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
        float dd = calcSDF( aopos ).x;
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
        float h = calcSDF(ro + rd*t).x;
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
    vec2 dist = calcSDF(pos);
    vec2 e = vec2(EPSILON, 0.0);

    vec3 normal = dist.x - vec3(
        calcSDF(pos-e.xyy).x,
        calcSDF(pos-e.yxy).x,
        calcSDF(pos-e.yyx).x);

    return vec4(normalize(normal), dist.y);
}


float rMarch(vec3 rOrig, vec3 rDir) {
    float dOrig = 0.0; // distance from ray origin

    for(int i=0; i<MAX_STEPS; i++) {
        vec3 rPos = rOrig + rDir * dOrig;
        float dSurf = calcSDF(rPos).x;
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

    vec3 color = getMaterial(p, N.w, N.xyz, 0.5);
    //vec3 color = vec3(0); //TEMPORARY

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

        vec3 material = getMaterial(pos, matID, normal, 0.5);

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

void main() {
    vec2 uv = getUV(vec2(0.0));

    vec3 rOrig = u_camPos; // Works with WASD without old camera rotation

    vec3 col = renderPixel(u_renderMode);

    col = pow(col, vec3( 1.0 / 2.2));	// gamma correction

    //col = vec3(uv,0.0);
    
    FragColor = vec4(col,1.0); 
}