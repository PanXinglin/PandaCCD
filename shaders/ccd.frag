#version 460 core
#include <flutter/runtime_effect.glsl>
// First vec2 and first sampler are bound automatically by ImageFilter.shader.
uniform vec2 uSize;
uniform float uStrength;
uniform float uGrain;
uniform float uTint;
uniform float uSaturation;
uniform float uContrast;
uniform float uVignette;
uniform float uBloom;
uniform float uSteps;
uniform float uBrightness;
uniform float uPixel;
uniform float uBeauty;
uniform float uBeautySmooth;
uniform float uBeautyEven;
uniform float uBeautyWhiten;
uniform float uFaceSlim;
uniform float uLutSide;
uniform float uCube;
uniform float uInputFlip;
uniform float uTrackFace;
// Eight face slots: bounding box and five jaw vectors per slot.
uniform vec4 uFaces[48];
uniform sampler2D uInput;
uniform sampler2D uLut;
out vec4 fragColor;

vec3 cell(vec3 p) {
  float index = p.r + p.g * uCube + p.b * uCube * uCube;
  vec2 pos = vec2(mod(index, uLutSide), floor(index / uLutSide));
  return texture(uLut, (pos + .5) / uLutSide).rgb;
}
vec3 hald(vec3 c) {
  vec3 p = clamp(c, 0., 1.) * (uCube - 1.);
  vec3 a = floor(p), b = min(a + 1., vec3(uCube - 1.)), f = fract(p);
  // Eight nearest lattice samples; interpolate RGB independently (HALD red-fastest).
  return mix(mix(mix(cell(a), cell(vec3(b.r,a.g,a.b)), f.r),
                 mix(cell(vec3(a.r,b.g,a.b)),cell(vec3(b.r,b.g,a.b)),f.r),f.g),
             mix(mix(cell(vec3(a.r,a.g,b.b)),cell(vec3(b.r,a.g,b.b)),f.r),
                 mix(cell(vec3(a.r,b.g,b.b)),cell(b),f.r),f.g), f.b);
}
float noise(vec2 p) { return fract(sin(dot(p,vec2(12.9898,78.233))) * 43758.5453); }
// Contour-driven inverse warp. Earlier versions adapted GPUPixel curveWarp
// (PixPark, Apache-2.0; attribution retained in assets/licenses). Independent
// radial pulls accumulated around the cheeks and also shortened the chin.
// Apply ONE bounded lateral displacement instead; never move pixels vertically.
vec2 jawPair(vec4 a,vec4 b,float t) {
  return mix(a.xz,b.xz,smoothstep(0.,1.,t));
}
vec2 slim(vec2 p,vec4 face,vec4 a,vec4 b,vec4 c,vec4 d,vec4 anchors) {
  if(face.z<=0. || uBeauty<=.001 || uFaceSlim<=.001 || anchors.y<=anchors.w)return p;
  float depth=anchors.y-anchors.w;
  float t=(p.y-anchors.w)/depth;
  // Preserve the cheeks above the lips and the rounded bottom of the chin.
  float envelope=smoothstep(.02,.32,t)*(1.-smoothstep(.48,.88,t));
  if(envelope<=0.)return p;
  vec2 edges;
  if(t<.35) edges=jawPair(a,b,clamp((t-.08)/.27,0.,1.));
  else if(t<.62) edges=jawPair(b,c,(t-.35)/.27);
  else edges=jawPair(c,d,clamp((t-.62)/.23,0.,1.));
  float center=(edges.x+edges.y)*.5;
  float halfWidth=(edges.y-edges.x)*.5;
  if(halfWidth<=.001)return p;
  float x=(p.x-center)/halfWidth;
  // Central features stay still; the surrounding pixels blend back smoothly.
  float lateral=smoothstep(.35,.95,abs(x))*(1.-smoothstep(1.05,1.65,abs(x)));
  float strength=clamp(uFaceSlim,0.,1.);
  // Keep the low end subtle and give the upper half of the slider more range.
  float amount=mix(.08,.14,strength)*strength*sqrt(clamp(uBeauty,0.,1.));
  return p+vec2(sign(x)*halfWidth*amount*envelope*lateral,0.);
}
float faceArea(vec2 p,vec4 face) {
  if(face.z<=0.)return 0.;
  vec2 d=(p-(face.xy+face.zw*vec2(.5,.48)))/max(face.zw*vec2(.53,.65),vec2(.001));
  return 1.-smoothstep(.72,1.05,length(d));
}
void applyFace(vec2 uv, vec4 face, vec4 a, vec4 b, vec4 c, vec4 d, vec4 anchors,
               inout float area, inout float displacement, inout float weight) {
  if (face.z <= 0.) return;
  if (uTrackFace > .5) area = max(area, faceArea(uv, face));
  float dx = slim(uv, face, a, b, c, d, anchors).x - uv.x;
  // Blend overlapping warps without stacking their strength on shared pixels.
  float w = abs(dx);
  displacement += dx * w;
  weight += w;
}
#define APPLY_FACE(i) applyFace(uv, uFaces[i], uFaces[i+1], uFaces[i+2], uFaces[i+3], uFaces[i+4], uFaces[i+5], area, displacement, weight)
void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float area = uTrackFace > .5 ? 0. : 1.;
  float displacement = 0., weight = 0.;
  if (uBeauty > .001) {
    APPLY_FACE(0);
    APPLY_FACE(6);
    APPLY_FACE(12);
    APPLY_FACE(18);
    APPLY_FACE(24);
    APPLY_FACE(30);
    APPLY_FACE(36);
    APPLY_FACE(42);
  }
  vec2 sampleUv = uv + vec2(displacement / max(weight, .000001), 0.);
  if (uPixel > .01) {
    vec2 grid = vec2(mix(1200., 160., uPixel), mix(1600., 213., uPixel));
    sampleUv = (floor(sampleUv * grid) + .5) / grid;
  }
  #ifdef IMPELLER_TARGET_OPENGLES
    if(uInputFlip > .5) sampleUv.y = 1. - sampleUv.y;
  #endif
  vec4 src = texture(uInput, sampleUv);
  vec3 raw = src.rgb / max(src.a, .001);
  float skinBeauty = 0.;
  if (uBeauty > .001 && area>.001) {
    // Multi-scale, edge-aware smoothing: a wider support actually reduces
    // blemishes instead of averaging only the immediately adjacent texels.
    // Coordinates use the short edge so portrait/landscape have equal strength.
    float radius = max(1.25, min(uSize.x,uSize.y) * .0028);
    vec2 delta = vec2(radius) / uSize;
    vec3 sum = raw;
    float weights = 1.;
    for (int y = -2; y <= 2; y++) {
      for (int x = -2; x <= 2; x++) {
        if (x == 0 && y == 0) continue;
        vec2 offset = vec2(float(x),float(y));
        vec4 neighbor = texture(uInput, clamp(sampleUv + offset * delta, vec2(0.), vec2(1.)));
        vec3 color = neighbor.rgb / max(neighbor.a, .001);
        vec3 diff = color - raw;
        float spatial = 1. / (1. + dot(offset,offset) * .25);
        // Softer range weighting lets small red/dark blemishes blend out while
        // high-contrast eye/hair boundaries contribute almost no color.
        float weight = exp(-dot(diff,diff) * 24.) * spatial;
        sum += color * weight;
        weights += weight;
      }
    }
    vec3 smoothColor = sum / weights;
    // Derive the mask from the local skin tone too: a blemish must not exclude
    // itself from smoothing just because it is redder than surrounding skin.
    vec3 maskColor = mix(raw,smoothColor,.7);
    float cb = .5 + dot(maskColor, vec3(-.168736,-.331264,.5));
    float cr = .5 + dot(maskColor, vec3(.5,-.418688,-.081312));
    float skin = smoothstep(.27,.34,cb) * (1.-smoothstep(.53,.59,cb)) *
      smoothstep(.50,.55,cr) * (1.-smoothstep(.76,.84,cr));
    float light = dot(maskColor,vec3(.299,.587,.114));
    skin *= smoothstep(.04,.14,light) * (1.-smoothstep(.91,1.,light));
    float amount = sqrt(clamp(uBeauty,0.,1.));
    skinBeauty = skin * amount * area;
    // Preserve strong boundaries, soften fine texture and local unevenness.
    float edge = length(raw - smoothColor);
    float edgeKeep = 1. - smoothstep(.12,.26,edge);
    raw = mix(raw,smoothColor,skinBeauty * clamp(uBeautySmooth*1.34,0.,.98) * edgeKeep);
    // Gentle shadow lift and yellow-cast correction. Smoothing remains the
    // primary visible effect; the highlight rolloff prevents a washed-out face.
    vec3 lifted = log(vec3(1.) + .45 * raw) / log(1.45);
    raw = mix(raw,lifted,skinBeauty * uBeautyWhiten * 1.5);
    float yellow = max(min(raw.r,raw.g) - raw.b,0.);
    raw += vec3(.006,.002,.022) * skinBeauty * uBeautyEven * 2.22;
    raw.b += yellow * skinBeauty * .13 * uBeautyEven * 2.22;
  }
  vec3 c = hald(raw);
  c += vec3(uTint - .5, 0., .5 - uTint) * .18;
  c = (c - .5) * (.5 + uContrast) + .5 + (uBrightness - .5) * .65;
  float luma = dot(c, vec3(.299,.587,.114));
  c = mix(vec3(luma), c, uSaturation * 2.);
  // Halation: neighboring bright pixels bleed into the local image.
  vec2 d = vec2(2.) / uSize;
  vec3 glow = (texture(uInput, sampleUv + vec2(d.x,0.)).rgb +
    texture(uInput, sampleUv - vec2(d.x,0.)).rgb +
    texture(uInput, sampleUv + vec2(0.,d.y)).rgb +
    texture(uInput, sampleUv - vec2(0.,d.y)).rgb) * .25;
  c += max(glow - .65, 0.) * uBloom * .8;
  if (uSteps > .01) {
    float levels = mix(128., 8., uSteps);
    vec2 tile = mod(floor(uv * uSize), 2.);
    float bayer = mod(tile.x + tile.y, 2.) * 2. + tile.y;
    vec3 quantized = floor(c * levels + bayer * .25) / levels;
    c = mix(quantized,c,skinBeauty * .8);
  }
  // Fixed sensor grain keeps preview and exported still deterministic.
  c += (noise(floor(uv * vec2(960.,1280.))) - .5) * uGrain * .22 * (1. - skinBeauty * .85);
  c *= 1. - smoothstep(.2,.72,length(uv-.5)) * uVignette * .7;
  fragColor = vec4(mix(raw * src.a,clamp(c,0.,1.) * src.a,uStrength),src.a);
}
