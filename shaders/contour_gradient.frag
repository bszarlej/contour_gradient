// Colors a border with a gradient that runs along it.
//
// uMap holds, for each pixel around the border, how far along the border it
// is, as a fraction of the border's length in 24 bits: the red, green and
// blue bytes, most significant first. uGradient is one period of the
// gradient, one pixel high.
//
// Both images are sampled at the centres of their pixels and blended here,
// so the result does not depend on how the engine filters them.

#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

// Where pixel (0, 0) of the map starts, in the canvas's coordinates.
uniform vec2 uOrigin;
// Pixels of the map per logical pixel.
uniform float uScale;
// The size of the map, in pixels.
uniform vec2 uMapSize;
// How far the gradient is moved along the border, as a fraction of its
// length.
uniform float uOffset;
uniform sampler2D uMap;
uniform sampler2D uGradient;

out vec4 fragColor;

const float kGradientWidth = 4096.0;

vec4 gradientPixel(float i) {
  float x = (mod(i, kGradientWidth) + 0.5) / kGradientWidth;
  return texture(uGradient, vec2(x, 0.5));
}

void main() {
  vec2 pixel = clamp(
    floor((FlutterFragCoord().xy - uOrigin) * uScale),
    vec2(0.0),
    uMapSize - 1.0
  );
  vec3 bytes = floor(texture(uMap, (pixel + 0.5) / uMapSize).rgb * 255.0 + 0.5);
  float along = dot(bytes, vec3(65536.0, 256.0, 1.0)) / 16777216.0;
  // The gradient repeats, with its pixels centred on their positions.
  float x = fract(along + uOffset) * kGradientWidth - 0.5;
  float i = floor(x);
  fragColor = mix(gradientPixel(i), gradientPixel(i + 1.0), x - i);
}
