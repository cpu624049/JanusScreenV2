// Enhanced foveation with multiple pattern options
// Flutter uniforms:
//  uResolution: viewport size (width, height)
//  uCenter: focus center in pixels (x, y)
//  uRadius: inner clear radius in px
//  uFeather: transition width in px
//  uGrain: grain intensity [0..1]
//  uPatternType: pattern type [0=noise, 1=hatch, 2=dot, 3=wave]

precision mediump float;

uniform vec2 uResolution;
uniform vec2 uCenter;
uniform float uRadius;
uniform float uFeather;
uniform float uGrain;
uniform float uPatternType;

out vec4 fragColor;

float hash(vec2 p){
	p = fract(p*vec2(123.34, 345.45));
	p += dot(p, p+34.345);
	return fract(p.x*p.y);
}

float noise(vec2 p) {
	return hash(p);
}

float hatch(vec2 p, float scale) {
	vec2 grid = fract(p * scale);
	return step(0.5, grid.x) * step(0.5, grid.y);
}

float dots(vec2 p, float scale) {
	vec2 grid = fract(p * scale);
	float dist = distance(grid, vec2(0.5));
	return 1.0 - smoothstep(0.0, 0.3, dist);
}

float waves(vec2 p, float scale) {
	return sin(p.x * scale) * sin(p.y * scale) * 0.5 + 0.5;
}

void main() {
	vec2 uv = gl_FragCoord.xy;
	float d = distance(uv, uCenter);
	float edge0 = uRadius;
	float edge1 = uRadius + max(1.0, uFeather);
	float t = clamp((d - edge0) / (edge1 - edge0), 0.0, 1.0);

	// Base vignette
	float shade = mix(0.0, 0.35, t*t);
	
	// Pattern overlay
	float pattern = 0.0;
	float patternScale = 0.02;
	
	if (uPatternType < 0.5) {
		// Noise pattern
		pattern = (noise(uv) - 0.5) * 2.0;
	} else if (uPatternType < 1.5) {
		// Hatch pattern
		pattern = hatch(uv, patternScale * 8.0) - 0.5;
	} else if (uPatternType < 2.5) {
		// Dot pattern
		pattern = dots(uv, patternScale * 6.0) - 0.5;
	} else {
		// Wave pattern
		pattern = waves(uv, patternScale * 4.0) - 0.5;
	}
	
	float g = pattern * uGrain * t;
	fragColor = vec4(vec3(-shade + g), 0.0);
}

