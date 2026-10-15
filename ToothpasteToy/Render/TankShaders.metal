// TankShaders.metal — OWNER: HOLO (Documentation/REDESIGN-OWNERSHIP.md §3).
// App fragments linked with LabKit's `labQuadVertex` (vertex from the LabKit metallib, fragment from the app's).
// LabKitShaderLib.h comes from MTL_HEADER_SEARCH_PATHS (project.yml).
//
// The holo chamber (REDESIGN.md §2): the projection volume's back (Metro canvas, a faint technical grid at two depths
// that slides against the hologram under tilt, the projector's light cone), the opaque metal housing around it (Metro
// metal recipe: dark broad faces, light only at the lit chamfer, grooves, calibration ticks and the corner screws), the
// projector emitter (a thin metal lip with a cyan light slit) under the floor, the knurled tube nozzle at the top, and the
// lens's refraction of everything behind the hologram (Metro spec §14: bounded refraction, a magnifier, colour split
// only at diagonal edges). The hologram itself is LabKitMPM's `flHoloFragment`.
//
// Every fragment here reads `ToothpasteTankUniforms` at fragment buffer 1 (LabFragmentApp, mirrored in TankRenderer.swift).
// Units: tank metres (origin at the inside bottom-left, y up). Colours are linear extended Display P3; broad areas stay
// far below LabKit's bloom prefilter (0.35), only the slit, the lit chamfer line and the nozzle's mouth reach it.

#include <metal_stdlib>
#include "LabKitShaderLib.h"
using namespace metal;

struct ToothpasteTankUniforms {
    float4 tank;       // x width (m), y height (m), z drawable px per metre, w time (s)
    float4 origin;     // xy drawable px of the tank origin (y down), zw drawable size (px)
    float4 keyLight;   // xyz toward the key light (screen frame, z out of the screen), w intensity
    float4 fillLight;  // xyz, w intensity
    float4 up;         // xyz world up in the screen frame, w reduce motion (1)
    float4 fluid;      // rgb the paste's hologram body light (linear), a opacity of its Solid look
    float4 tilt;       // xy bounded tilt e (spring-smoothed), zw the near grid's parallax offset (m)
    float4 stage;      // x vibration 0–1, y vibration phase (rad), z magnet field 0–1, w magnet x (m)
    float4 projector;  // x slit gain, y light-cone gain, z cone drift time (s), w hologram style (1) or Solid (0)
    float4 field;      // fluid surface field rect for props: origin xy, size zw (drawable px); zero = none
    float4 misc;       // x cell size (m), y iso level, z drawable px per point, w far grid parallax scale
    float4 lens;       // xy centre (m), z radius (m), w refraction strength 0–1
    float4 lensOptics; // xy tilt shift at the centre (m), z magnification k, w red-to-blue split (m)
    float4 nozzle;     // x mouth centre x (m), y mouth y (m), z bore radius (m), w mouth light 0–1
    float4 accent;     // rgb the paste's rim light (linear), a squeezing (0–1)
};

constexpr sampler toothpasteLinear(filter::linear, address::clamp_to_edge);
constexpr sampler toothpasteMip(filter::linear, mip_filter::linear, address::clamp_to_edge);

// Linear Metro colours (MetroTokens.swift decodes the same canonical sRGB doubles).
constant float3 kCanvas = float3(0.00193, 0.00325, 0.00464);       // canvas #060B0F
constant float3 kHousing = float3(0.00209, 0.00317, 0.00439);      // gauge housing #070A0E
constant float3 kMetalLight = float3(0.00478, 0.00654, 0.00857);   // metal light #0E1317
constant float3 kCyan = float3(0.0844, 0.807, 0.913);              // instrument cyan #52E8F5
constant float3 kInk = float3(0.319, 0.434, 0.493);                // secondary ink #99B0BA
constant float3 kMint = float3(0.10, 0.80, 0.50);                  // the icon's matrix mesh, a mint phosphor
constant float kSlitHalf = 0.34;                                   // the emitter slit spans ±34 % of the floor's width

// Tank metres of a drawable pixel.
static inline float2 toothpasteTankPoint(float2 px, constant ToothpasteTankUniforms& t) {
    return float2(px.x - t.origin.x, t.origin.y - px.y) / max(t.tank.z, 1e-3);
}

static inline float toothpasteQuintic(float x) { x = saturate(x); return x * x * x * (x * (x * 6.0 - 15.0) + 10.0); }

// The same soft studio as the fluid's Solid look (MPMRender.metal flStudioEnv): a soft box overhead, a dark floor.
static inline float3 toothpasteStudio(float3 r, float3 up) {
    float y = dot(r, up);
    float3 side = normalize(cross(up, float3(0, 0, 1)) + float3(1e-4, 0, 0));
    float x = dot(r, side);
    float3 c = mix(float3(0.010, 0.011, 0.016), float3(0.06, 0.065, 0.085), smoothstep(-0.3, 0.4, y));
    c += float3(0.18, 0.20, 0.24) * exp(-y * y * 140.0);
    c += float3(1.0) * smoothstep(0.88, 0.97, y) * (1.0 - smoothstep(0.22, 0.38, abs(x)));
    c += float3(0.45, 0.34, 0.24) * smoothstep(0.80, 0.95, x) * (1.0 - smoothstep(0.1, 0.45, abs(y)));
    return c;
}
static inline float3 toothpasteEnvUp(constant ToothpasteTankUniforms& t) { return normalize(t.up.xyz + float3(0, 0.6, 0)); }

static inline float toothpasteGGX(float3 n, float3 v, float3 l, float rough) {
    float3 h = normalize(l + v);
    float NoL = saturate(dot(n, l)), NoV = max(dot(n, v), 1e-3), NoH = saturate(dot(n, h));
    float a = max(rough * rough, 2e-3), a2 = a * a;
    float d = NoH * NoH * (a2 - 1.0) + 1.0;
    float k = (rough + 1.0) * (rough + 1.0) / 8.0;
    // Clamped: a single-pixel peak would bloom into a visible square at the post chain's ¼ resolution.
    return min(a2 / (M_PI_F * d * d) / ((NoL * (1.0 - k) + k) * (NoV * (1.0 - k) + k)) * 0.25 * NoL, 0.6);
}

// A thin anti-aliased line at distance `d` (m) with half width `w` (m); `fw` = metres per pixel.
static inline float toothpasteLine(float d, float w, float fw) {
    return 1.0 - smoothstep(w, w + fw * 1.1, abs(d));
}

// MARK: - Chamber (pass 1): the projection volume and its housing, one opaque quad over the whole drawable

/// The projection volume at tank point `p` (m): Metro canvas, a mint technical grid on the chamber's back at depth
/// (10 mm lines and 2 mm minor lines, sliding against the hologram with the tilt), a fainter, deeper dot lattice, and
/// the projector's light cone rising from the slit (brightest on the floor, with slow light shafts); the housing shades
/// it near the walls and the light fades toward the top corners.
static inline float3 toothpasteVolume(float2 p, constant ToothpasteTankUniforms& t, float mpp) {
    float W = t.tank.x, H = t.tank.y;
    bool reduce = t.up.w > 0.5;
    float3 vol = kCanvas;
    // Grid on the back, at depth: it slides against the hologram as the phone tilts (spring-smoothed in Swift).
    float2 g = p + t.tilt.zw;
    float major = max(labLineMask(g.x, 0.010, mpp), labLineMask(g.y, 0.010, mpp));
    float minor = max(labLineMask(g.x, 0.002, mpp * 0.8), labLineMask(g.y, 0.002, mpp * 0.8));
    // A deeper lattice of points every 5 mm (twice the parallax: further away).
    float2 gd = p + t.tilt.zw * t.misc.w;
    float2 cell = fract(gd / 0.005 + 0.5) - 0.5;
    float dots = 1.0 - smoothstep(0.6 * mpp, 1.6 * mpp, length(cell) * 0.005);
    // The projector's light: a beam fanning up from the emitter slit under the floor (the slit spans the middle
    // `kSlitHalf` of the floor; the beam's sides open to the walls at the top), brightest at the floor, with slow light
    // shafts and a thin brighter line along each side (the projection's frustum). The mesh glows where it reaches.
    float rise = max(p.y, 0.0);
    float drift = reduce ? 0.0 : t.projector.z;
    float halfW = W * (kSlitHalf + (0.5 - kSlitHalf) * saturate(rise / max(H, 1e-4)));
    float across = abs(p.x - 0.5 * W);
    float side = across - halfW;                                             // m, < 0 inside the beam
    float inBeam = 1.0 - smoothstep(-0.004, 0.0015, side);
    float sideLine = exp(-abs(side) / max(1.2 * mpp, 1e-6)) * smoothstep(0.004 * H, 0.06 * H, rise);
    float shafts = 0.62 + 0.38 * (0.5 + 0.5 * sin(p.x / 0.0042 * 6.2831853 + 1.7 * sin(p.x / 0.011 + drift * 0.35)))
                        * (0.5 + 0.5 * sin(p.x / 0.0017 * 6.2831853 - drift * 0.6));
    float fall = exp(-rise / 0.034) * 0.70 + exp(-rise / 0.0040) * 0.30;
    float cone = (fall * inBeam * shafts + sideLine * 0.22 * exp(-rise / 0.06)) * t.projector.y;
    float meshLight = 1.0 + 2.6 * exp(-rise / 0.020) * inBeam * t.projector.y;
    vol += kMint * (major * 0.020 + minor * 0.0055) * meshLight;
    vol += kMint * dots * 0.010;
    vol += kCyan * cone * 0.045;
    // The housing shades the volume near its walls (the window's frame is raised above the back).
    float2 hw = float2(W, H) * 0.5;
    float2 q = p - hw;
    float2 dd = abs(q) - hw;
    float sdIn = min(max(dd.x, dd.y), 0.0);
    vol *= 0.55 + 0.45 * smoothstep(0.0, 0.0022, -sdIn);
    // A faint vignette toward the top corners: the light comes from below.
    vol *= 1.0 - 0.35 * smoothstep(0.35, 1.0, p.y / max(H, 1e-4)) * (0.6 + 0.4 * abs(q.x) / max(hw.x, 1e-4));
    return vol;
}

/// Inside the tank: the projection volume, refracted under the glass lens (Metro spec §14 applied to the chamber
/// itself, so no copy of the scene is needed: the bounded tilt shift with its smooth feather, a gentle magnifier toward
/// the centre, and red and blue taken ± a split only at the lens's diagonal edges; the hologram's shade refracts the
/// paste with the same numbers, so both line up). Outside it: the housing — opaque blue-black metal with a lit chamfer
/// round the window, a groove, millimetre calibration ticks down the left and along the bottom, screws in the corners
/// and, under the floor, the projector's lip with its cyan slit. Pixels wholly inside skip the housing.
fragment float4 toothpasteChamberFragment(LabQuadOut in [[stage_in]], constant ToothpasteTankUniforms& t [[buffer(LabFragmentApp)]]) {
    float2 px = in.position.xy;
    float2 p = toothpasteTankPoint(px, t);
    float W = t.tank.x, H = t.tank.y;
    float mpp = 1.0 / max(t.tank.z, 1.0);                                    // metres per drawable pixel
    // Signed distance to the window (the tank's inside), m: negative inside.
    float2 hw = float2(W, H) * 0.5;
    float2 q = p - hw;
    float2 dd = abs(q) - hw;
    float sd = length(max(dd, 0.0)) + min(max(dd.x, dd.y), 0.0);
    float inside = 1.0 - smoothstep(-0.5 * mpp, 0.5 * mpp, sd);

    // ---- The projection volume (and the lens over it)
    float3 vol = 0.0;
    if (inside > 0.0) {
        float2 c = t.lens.xy;
        float R = max(t.lens.z, 1e-5);
        float2 d = (p - c) / R;
        float r = length(d);
        if (t.lens.w > 0.001 && r < 1.0) {
            float s = t.lens.w;
            float feather = 1.0 - toothpasteQuintic((r - 0.82) / 0.18);
            float weight = feather * (1.0 - 0.32 * r * r);
            float m = (1.0 - r * r) * (1.0 - r * r);
            float2 src = p - (p - c) * (t.lensOptics.z * m * s) - t.lensOptics.xy * (weight * s);
            float window = r < 0.82 ? toothpasteQuintic((r - 0.52) / 0.30) : 1.0 - toothpasteQuintic((r - 0.82) / 0.18);
            float diag = r > 1e-4 ? 2.0 * d.x * d.y / (r * r) : 0.0;
            float2 radial = r > 1e-4 ? d / r : float2(0.0);
            float2 split = (t.tilt.xy * 0.5 + radial * 0.25) * t.lensOptics.w * window * diag * diag * s;
            vol = toothpasteVolume(src, t, mpp);
            if (abs(split.x) + abs(split.y) > 1e-8) {
                vol.r = toothpasteVolume(src + split, t, mpp).r;
                vol.b = toothpasteVolume(src - split, t, mpp).b;
            }
        } else {
            vol = toothpasteVolume(p, t, mpp);
        }
    }
    if (inside >= 1.0) return float4(vol, 1.0);

    // ---- The housing
    float e = max(sd, 0.0);                                                  // m outside the window
    // Which band: the nearest window edge and its outward normal.
    float2 outward = dd.x > dd.y ? float2(sign(q.x), 0.0) : float2(0.0, sign(q.y));
    // Directional light in the screen plane, from the upper left, turning a little with the tilt.
    float la = 2.25 - t.tilt.x * 0.35;
    float2 light = float2(cos(la), sin(la));
    float3 metal = kHousing;
    // Brushed face: a fine grain along the band (very low contrast).
    float2 brushAxis = abs(outward.x) > 0.5 ? float2(0.0, 1.0) : float2(1.0, 0.0);
    float along = dot(p, brushAxis), across = dot(p, float2(brushAxis.y, brushAxis.x));
    float brush = labNoise(float3(across / 0.00004, along / 0.004, 3.0));
    metal *= 0.86 + 0.28 * brush;
    // Lit chamfer round the window (0.75 mm): its face looks back into the volume (−outward); light from the key side.
    const float chamfer = 0.00075;
    float onChamfer = 1.0 - smoothstep(chamfer - 0.5 * mpp, chamfer + 0.5 * mpp, e);
    float lit = saturate(dot(-outward, light));
    float3 chamferC = kMetalLight * (1.4 + 9.0 * lit * lit) * (0.75 + 0.25 * smoothstep(0.0, chamfer, e));
    metal = mix(metal, chamferC, onChamfer);
    // Edge highlights: a crisp line at the window's lip (white 0.36 on the lit side) and a darker one at the chamfer's
    // outer edge (the metal recipe's rim: light, near-clear, black).
    metal += float3(0.11) * toothpasteLine(e, 0.35 * mpp, mpp) * (0.25 + 0.75 * lit);
    metal *= 1.0 - 0.6 * toothpasteLine(e - chamfer, 0.35 * mpp, mpp);
    // A groove 1.6 mm out (dark line, light lip just outside: white 0.07).
    float groove = e - 0.0016;
    metal *= 1.0 - 0.55 * toothpasteLine(groove, 0.4 * mpp, mpp);
    metal += float3(0.0049) * toothpasteLine(groove - 1.1 * mpp, 0.35 * mpp, mpp) * (0.4 + 0.6 * saturate(dot(outward, light) + 0.5));
    // Calibration: millimetre ticks down the left band and along the bottom band (1 mm, 5 mm, 10 mm), in secondary
    // ink; 5 mm ticks on the right band. Ticks stand between the chamfer and the groove's far side.
    float3 tickC = kInk * 0.20;
    float ticks = 0.0;
    if (outward.x < -0.5 && p.y > 0.0 && p.y < H) {
        float mm = p.y * 1000.0, k = floor(mm + 0.5);
        bool ten = fmod(k, 10.0) < 0.5, five = fmod(k, 5.0) < 0.5;
        float len = ten ? 0.0016 : (five ? 0.0011 : 0.0006);
        float w = (ten ? 0.55 : 0.4) * mpp;
        ticks = toothpasteLine((mm - k) * 0.001, w, mpp) * step(chamfer + 0.0002, e) * step(e, chamfer + 0.0002 + len)
              * (ten ? 1.6 : (five ? 1.2 : 0.8));
    } else if (outward.x > 0.5 && p.y > 0.0 && p.y < H) {
        float k = floor(p.y / 0.005 + 0.5);
        bool ten = fmod(k, 2.0) < 0.5;
        float len = ten ? 0.0012 : 0.0007;
        ticks = toothpasteLine(p.y - k * 0.005, 0.45 * mpp, mpp) * step(chamfer + 0.0002, e) * step(e, chamfer + 0.0002 + len);
    }
    metal += tickC * ticks;

    // The projector under the floor: a dark glass window (1.1 mm) with the cyan light slit, then a lit metal lip.
    if (p.y < 0.0) {
        float y = -p.y;
        float slitHalf = W * kSlitHalf;
        float span = 1.0 - smoothstep(slitHalf - 0.0012, slitHalf, abs(p.x - 0.5 * W));
        float inWindow = (1.0 - smoothstep(0.0011 - 0.5 * mpp, 0.0011 + 0.5 * mpp, y)) * step(0.0, p.x) * step(p.x, W);
        float3 window = float3(0.0010, 0.0018, 0.0024);
        // The slit: a thin bright core, a soft halo; a static lenslet pattern along it; ripples while the floor shakes.
        float sy = (y - 0.00048) / 0.00011;
        float lenslets = 0.88 + 0.12 * cos(p.x / 0.0009 * 6.2831853);
        float shake = t.stage.x > 0.001 ? 1.0 + 0.35 * t.stage.x * sin(p.x / 0.006 * 6.2831853 + t.stage.y) : 1.0;
        float core = exp(-sy * sy) * span * lenslets * shake;
        float halo = exp(-abs(y - 0.00048) / 0.00035) * span * 0.25;
        float3 slit = kCyan * (core * 3.2 + halo) * t.projector.x;
        float3 win = window + slit;
        // The lip: a lit edge on top (it faces up into the light), grooves, then the housing face below.
        float lipTop = y - 0.0011;
        float3 lip = metal + float3(0.020, 0.024, 0.028) * toothpasteLine(lipTop - 0.6 * mpp, 0.45 * mpp, mpp);
        // The x scale hangs from the lip: 5 mm ticks, 10 mm longer.
        float kx = floor(p.x / 0.005 + 0.5);
        bool ten = fmod(kx, 2.0) < 0.5;
        float len = ten ? 0.0013 : 0.0008;
        float tickX = toothpasteLine(p.x - kx * 0.005, (ten ? 0.55 : 0.42) * mpp, mpp) * step(0.0019, y) * step(y, 0.0019 + len)
                    * step(0.0, p.x) * step(p.x, W);
        lip += tickC * tickX * (ten ? 1.6 : 1.1);
        metal = mix(lip, win, inWindow);
    }
    // The rail the nozzle's carriage runs in, across the top band: a dark slot with a lit lower lip.
    if (p.y > H) {
        float ry = p.y - (H + 0.0017);
        float span = step(0.003, p.x) * step(p.x, W - 0.003);
        float slot = (1.0 - smoothstep(0.00045 - 0.5 * mpp, 0.00045 + 0.5 * mpp, abs(ry))) * span;
        metal = mix(metal, float3(0.0006, 0.0008, 0.0010), slot);
        metal += float3(0.010, 0.012, 0.014) * toothpasteLine(ry + 0.00045 + 0.6 * mpp, 0.35 * mpp, mpp) * span;
    }
    // Screws at the housing's corners (bearings: where metal detail belongs).
    float2 corner = float2(p.x < hw.x ? -0.0013 : W + 0.0013, p.y < hw.y ? -0.0035 : H + 0.0019);
    float2 sc = p - corner;
    float rs = length(sc);
    float screw = 1.0 - smoothstep(0.00062 - 0.5 * mpp, 0.00062 + 0.5 * mpp, rs);
    if (screw > 0.0) {
        float2 n2 = rs > 1e-6 ? sc / rs : float2(0.0);
        float dome = 1.0 - rs / 0.00062;
        float3 s = kMetalLight * (1.2 + 5.0 * saturate(dot(n2, light)) * (1.0 - dome)) ;
        float slot = toothpasteLine(dot(sc, float2(0.7071, 0.7071)), 0.00009, mpp) * step(rs, 0.00048);
        s *= 1.0 - 0.7 * slot;
        metal = mix(metal, s, screw * (1.0 - inside));
    }

    float3 c = mix(metal, vol, inside);
    return float4(c, 1.0);
}

// MARK: - Nozzle (pass 2, over the hologram): the tube's tip on its shaft, from the carriage in the top band

// Polished steel across a cylinder (u = −1…1 across it): dark broad face, a key-light streak, a soft fill.
static inline float3 toothpasteSteel(float u, constant ToothpasteTankUniforms& t) {
    float3 n = float3(u, 0.0, sqrt(max(1.0 - u * u, 0.0)));
    float3 key = normalize(t.keyLight.xyz);
    float spec = pow(saturate(dot(reflect(-float3(0, 0, 1), n), key)), 24.0);
    float diff = saturate(dot(n, key));
    return float3(0.030, 0.036, 0.042) * (0.35 + 0.65 * diff) + float3(0.30, 0.34, 0.38) * spec
         + float3(0.010, 0.012, 0.014) * (1.0 - abs(u));
}

/// The tube rides down into the chamber to lay its ribbon (PLAY's Tube: `NozzleState.position` is the mouth). Drawn as
/// an instrument: a slim polished shaft from a carriage that runs in a rail in the housing's top band, a conical
/// shoulder, and the tip — a cylinder the bore's width with a knurled collar (40 ridges, crossed) and a bright lip at
/// the mouth. While squeezing, cyan light spills from the mouth (the paste leaves the tube as projected light).
/// quad: x across the carriage, y from just below the mouth to the top of the band.
fragment float4 toothpasteNozzleFragment(LabQuadOut in [[stage_in]], constant ToothpasteTankUniforms& t [[buffer(LabFragmentApp)]]) {
    float2 p = toothpasteTankPoint(in.position.xy, t);
    float mpp = 1.0 / max(t.tank.z, 1.0);
    float H = t.tank.y;
    float cx = t.nozzle.x, mouth = t.nozzle.y, bore = max(t.nozzle.z, 0.0005);
    float x = p.x - cx, y = p.y - mouth;
    const float tipLen = 0.0040, collarLo = 0.0022, shoulder = 0.0015, shaftR = 0.0011;
    float tipR = bore + 0.0005, collarR = tipR + 0.00035;
    float3 c = float3(0.0);
    float a = 0.0;
    // Radius of the turned profile at this height (0 = nothing), and whether it is knurled.
    float R = 0.0;
    bool knurl = false;
    if (y >= 0.0 && y < collarLo) R = tipR;
    else if (y >= collarLo && y < tipLen) { R = collarR; knurl = true; }
    else if (y >= tipLen && y < tipLen + shoulder) R = mix(collarR, shaftR, toothpasteQuintic((y - tipLen) / shoulder));
    else if (y >= tipLen + shoulder && p.y < H + 0.0006) R = shaftR;
    if (R > 0.0) {
        float u = x / R;
        float edge = 1.0 - smoothstep(1.0 - mpp / R, 1.0, abs(u));
        if (edge > 0.0) {
            float3 steel = toothpasteSteel(u, t);
            float diff = saturate(dot(float3(u, 0.0, sqrt(max(1.0 - u * u, 0.0))), normalize(t.keyLight.xyz)));
            if (knurl) {
                float th = asin(clamp(u, -1.0, 1.0));
                float k1 = 0.5 + 0.5 * sin(th * 20.0 + p.y / 0.00045 * 3.14159);
                float k2 = 0.5 + 0.5 * sin(th * 20.0 - p.y / 0.00045 * 3.14159);
                steel *= 0.55 + 0.9 * k1 * k2;
                steel += float3(0.05, 0.055, 0.06) * (1.0 - smoothstep(0.00006, 0.00016, y - collarLo)) * diff;
            }
            // The mouth's lip: a bright ring line.
            steel += float3(0.16, 0.18, 0.20) * toothpasteLine(y - 0.00014, 0.00009, mpp) * (0.4 + 0.6 * diff);
            c = steel * edge;
            a = edge;
        }
    }
    // The carriage in the top band's rail: a rounded steel block with a lit top edge and a centre screw.
    float2 cq = float2(x, p.y - (H + 0.0017));
    float cs = labRoundedRectSDF(cq, float2(0.0034, 0.0011), 0.0005);
    float ca = 1.0 - smoothstep(-0.5 * mpp, 0.5 * mpp, cs);
    if (ca > 0.0) {
        float3 block = float3(0.022, 0.027, 0.032) + float3(0.06, 0.068, 0.075) * (1.0 - smoothstep(0.0, 0.0004, -cs)) * step(0.0, cq.y);
        float screw = 1.0 - smoothstep(0.00042 - mpp, 0.00042, length(cq));
        block = mix(block, float3(0.010, 0.012, 0.014) + float3(0.08) * toothpasteLine(cq.x + cq.y, 0.00007, mpp), screw);
        c = mix(c, block, ca);
        a = max(a, ca);
    }
    // The mouth light while squeezing: cyan below the mouth, additive (alpha 0).
    float2 m = (p - float2(cx, mouth - bore * 0.7)) / float2(bore * 0.85, bore * 1.3);
    float glow = exp(-dot(m, m) * 2.0) * (1.0 - smoothstep(mouth - 0.0006, mouth + 0.0001, p.y)) * t.nozzle.w;
    c += kCyan * glow * 0.65 * (1.0 - a);
    if (a <= 0.0 && glow < 1e-3) discard_fragment();
    return float4(c, a);
}

// MARK: - Metallic sheen (pass 2, over the fluid, Solid look only): MR fluid's oily steel gloss

/// MR fluid reads as a flat black slab at rest in the Solid look: its face lies flat against the front, so the surface
/// renderer's studio reflection is one uniform patch. This adds the room's reflection in the oily face, sliding with the
/// tilt, masked to the fluid by the surface renderer's field (texture 1). colour.a is its strength.
fragment float4 toothpasteSheenFragment(LabQuadOut in [[stage_in]], constant ToothpasteTankUniforms& t [[buffer(LabFragmentApp)]],
                                  texture2d<half> fieldG [[texture(1)]]) {
    if (t.field.z <= 0.0) discard_fragment();
    float2 fuv = (in.position.xy - t.field.xy) / t.field.zw;
    if (any(fuv < 0.0) || any(fuv > 1.0)) discard_fragment();
    float iso = t.misc.y;
    float rho = float(fieldG.sample(toothpasteLinear, fuv, level(0.0)).r);
    float inside = smoothstep(iso + 0.05, iso + 0.35, rho);
    if (inside <= 0.001) discard_fragment();
    float above = float(fieldG.sample(toothpasteLinear, fuv - float2(0.0, 0.035), level(0.0)).r);
    float nearTop = 1.0 - smoothstep(iso, iso + 0.6, above);
    float2 p = in.uv;
    float aspect = t.tank.y / max(t.tank.x, 1e-4);
    float2 q = float2(p.x, p.y * aspect) - float2(t.tilt.x * 0.25, -t.tilt.y * 0.2 * aspect);
    float d = dot(q, float2(0.62, 0.785));
    float fwD = fwidth(d);
    float bandA = smoothstep(0.30, 0.42 + fwD, d) * (1.0 - smoothstep(0.50, 0.74, d));
    float bandB = smoothstep(0.86, 0.88 + fwD, d) * (1.0 - smoothstep(0.92, 1.02, d));
    float k = in.color.a * inside;
    float3 steel = float3(0.62, 0.68, 0.78);
    return float4(steel * (bandA * 0.07 + bandB * 0.04 + nearTop * 0.04) * k, 0.0);
}

// MARK: - Props (pass 1 behind the hologram or translucent paste, pass 2 in front of opaque Solid paste)

/// params.w = kind·10 + face (kind 0 steel ball, 1 glass marble, 2 cork block, 3 die, 4 stir rod); params.y = angle.
static inline float4 toothpasteProp(LabQuadOut in, constant ToothpasteTankUniforms& t, texture2d<float> behind, bool front,
                              texture2d<half> fieldG) {
    float code = in.params.w;
    float kind = floor(code / 10.0 + 0.01);
    float face = code - kind * 10.0;
    float2 l = in.local;                                                      // body frame, metres
    float2 hs = in.halfSize;
    float angle = in.params.y;
    float cs = cos(angle), sn = sin(angle);
    float3 key = normalize(t.keyLight.xyz), fill = normalize(t.fillLight.xyz);
    float3 keyB = float3(cs * key.x + sn * key.y, -sn * key.x + cs * key.y, key.z);
    float3 fillB = float3(cs * fill.x + sn * fill.y, -sn * fill.x + cs * fill.y, fill.z);
    float3 upS = toothpasteEnvUp(t);
    float3 v = float3(0, 0, 1);
    float wet = 0.0;
    if (front && t.field.z > 0.0) {
        float2 fuv = (in.position.xy - t.field.xy) / t.field.zw;
        if (all(fuv >= 0.0) && all(fuv <= 1.0)) wet = smoothstep(t.misc.y - 0.05, t.misc.y + 0.15, float(fieldG.sample(toothpasteLinear, fuv, level(0.0)).r));
    }
    float3 c = 0.0;
    float a = 0.0;
    if (kind < 1.5) {                                                         // spheres
        float R = hs.x;
        float2 s = l / R;
        float r2 = dot(s, s);
        if (r2 > 1.0) discard_fragment();
        float aa = fwidth(sqrt(r2)) * 1.5;
        a = 1.0 - smoothstep(1.0 - aa, 1.0, sqrt(r2));
        float3 n = float3(s.x * cs - s.y * sn, s.x * sn + s.y * cs, sqrt(max(1.0 - r2, 0.0)));
        float3 r = reflect(-v, n);
        float NoV = saturate(n.z);
        if (kind < 0.5) {                                                     // polished steel: a mirror of the room
            float3 F0 = float3(0.62, 0.63, 0.65);
            float3 F = F0 + (1.0 - F0) * pow(1.0 - NoV, 5.0);
            float down = smoothstep(0.05, -0.55, dot(r, upS));
            float3 room = toothpasteStudio(r, upS) * 2.4 + float3(0.07, 0.075, 0.085) * (0.6 + 0.4 * saturate(dot(r, upS)));
            float3 goo = (t.fluid.a > 0.5 ? t.fluid.rgb * 0.6 : float3(0.06, 0.065, 0.08)) * down;
            c = mix(room, goo, down * 0.85) * F;
            c += (toothpasteGGX(n, v, key, 0.06) * t.keyLight.w + toothpasteGGX(n, v, fill, 0.10) * t.fillLight.w) * F * 2.5;
            c *= 0.85 + 0.15 * smoothstep(1.0, 0.6, sqrt(r2));
        } else {                                                              // glass marble with a cat's-eye vane
            float3 tint = float3(0.80, 0.92, 0.95);
            float3 F = 0.04 + 0.96 * pow(1.0 - NoV, 5.0);
            float3 seen;
            if (front && t.fluid.a > 0.5) {
                seen = t.fluid.rgb * (0.30 + 0.30 * saturate(0.5 - n.y * 0.6));
            } else if (front) {
                float2 uv = in.position.xy / t.origin.zw;
                float2 off = -float2(n.x, -n.y) * R * t.tank.z / t.origin.zw * 1.6;
                seen = behind.sample(toothpasteMip, uv + off, level(1.0)).rgb;
            } else {
                seen = mix(float3(0.045, 0.05, 0.065), float3(0.015, 0.018, 0.028), saturate(0.5 - n.y * 0.5));
            }
            c = seen * tint * (1.0 - F);
            float2 bl = l / R;
            float ribbon = exp(-pow(bl.y + 0.25 * sin(bl.x * 3.1), 2.0) * 60.0) * (1.0 - smoothstep(0.55, 0.85, length(bl)));
            float3 vane = mix(float3(0.85, 0.12, 0.35), float3(0.10, 0.60, 0.85), smoothstep(-0.6, 0.6, bl.x));
            c = mix(c, vane * (0.45 + 0.35 * n.z), ribbon * 0.85);
            c += toothpasteStudio(r, upS) * F * 1.2;
            c += toothpasteGGX(n, v, key, 0.04) * t.keyLight.w * 3.0 + toothpasteGGX(n, v, fill, 0.06) * t.fillLight.w * 1.5;
            c += float3(0.6, 0.8, 1.0) * 0.12 * pow(1.0 - NoV, 3.0);
        }
    } else {                                                                  // boxes: cork, die, rod
        float rr = in.params.z;
        float sd = labRoundedRectSDF(l, hs, rr);
        float aa = fwidth(sd) * 1.2;
        a = 1.0 - smoothstep(-aa, aa, sd);
        if (a <= 0.0) discard_fragment();
        float bev = kind > 3.5 ? min(hs.x, hs.y) : min(min(hs.x, hs.y) * 0.35, 0.0012);
        float2 e = float2(labRoundedRectSDF(l + float2(1e-5, 0), hs, rr) - labRoundedRectSDF(l - float2(1e-5, 0), hs, rr),
                          labRoundedRectSDF(l + float2(0, 1e-5), hs, rr) - labRoundedRectSDF(l - float2(0, 1e-5), hs, rr));
        float2 outward = length(e) > 1e-9 ? normalize(e) : float2(0);
        float tilt = saturate(1.0 + sd / bev);
        tilt = tilt * tilt * 0.85;
        float3 n = normalize(float3(outward * tilt, sqrt(max(1.0 - tilt * tilt, 0.05))));
        float dif = 0.25 + 0.75 * saturate(dot(n, keyB)) * t.keyLight.w * 0.8 + 0.3 * saturate(dot(n, fillB)) * t.fillLight.w;
        if (kind < 2.5) {                                                     // cork: warm granules and darker pits
            float2 g = l * 2600.0;
            float cell = labNoise(float3(g, 1.0)) * 0.6 + labNoise(float3(g * 2.3, 7.0)) * 0.4;
            float pits = smoothstep(0.62, 0.75, labNoise(float3(g * 1.4, 3.0)));
            float3 base = mix(float3(0.30, 0.17, 0.075), float3(0.52, 0.34, 0.17), cell);
            base *= 1.0 - 0.45 * pits;
            c = base * dif * 0.9;
            c += toothpasteGGX(n, v, keyB, 0.7) * t.keyLight.w * 0.15;
        } else if (kind < 3.5) {                                              // die: ivory with recessed pips
            float3 base = float3(0.80, 0.78, 0.72);
            float s = min(hs.x, hs.y);
            float2 u = l / s;
            int f = int(face + 0.5);
            float pip = 0.0;
            float pr = 0.19;
            float2 P[7] = { float2(0, 0), float2(-0.5, 0.5), float2(0.5, -0.5), float2(-0.5, -0.5), float2(0.5, 0.5),
                            float2(-0.5, 0), float2(0.5, 0) };
            for (int i = 0; i < 7; ++i) {
                bool on = (i == 0 && (f == 1 || f == 3 || f == 5)) || ((i == 1 || i == 2) && f >= 2) ||
                          ((i == 3 || i == 4) && f >= 4) || ((i == 5 || i == 6) && f == 6);
                if (!on) continue;
                float d = length(u - P[i]);
                pip = max(pip, 1.0 - smoothstep(pr - 0.03, pr, d));
            }
            float3 pipC = float3(0.035, 0.035, 0.045);
            c = mix(base * (0.8 + 0.25 * dif), pipC, pip);
            c += toothpasteGGX(n, v, keyB, 0.25) * t.keyLight.w * 0.6 * (1.0 - pip);
            c += float3(0.30, 0.25, 0.20) * 0.06 * (1.0 - tilt);
        } else {                                                              // stir rod: polished steel cylinder
            float across = clamp(l.y / max(hs.y, 1e-6), -1.0, 1.0);
            float3 nr = normalize(float3(-sn * across, cs * across, sqrt(max(1.0 - across * across, 0.05))));
            float3 F0 = float3(0.60, 0.61, 0.63);
            float3 r = reflect(-v, nr);
            c = toothpasteStudio(r, upS) * F0 * 1.4 + toothpasteGGX(nr, v, key, 0.1) * F0 * t.keyLight.w * 2.5 + F0 * 0.03;
        }
    }
    float skinBand = kind < 1.5 ? smoothstep(0.80, 0.92, length(l) / max(hs.x, 1e-6))
                                : smoothstep(-0.0016, -0.0004, labRoundedRectSDF(l, hs, in.params.z));
    float hug = wet * saturate(t.fluid.a) * mix(0.25, 0.9, skinBand);
    c = mix(c, t.fluid.rgb * 0.72, hug);
    return float4(c * a, a);
}

fragment float4 toothpastePropFragment(LabQuadOut in [[stage_in]], constant ToothpasteTankUniforms& t [[buffer(LabFragmentApp)]],
                                 texture2d<float> behind [[texture(0)]], texture2d<half> fieldG [[texture(1)]]) {
    return toothpasteProp(in, t, behind, false, fieldG);
}
fragment float4 toothpastePropFrontFragment(LabQuadOut in [[stage_in]], constant ToothpasteTankUniforms& t [[buffer(LabFragmentApp)]],
                                      texture2d<float> behind [[texture(0)]], texture2d<half> fieldG [[texture(1)]]) {
    return toothpasteProp(in, t, behind, true, fieldG);
}

// MARK: - Overlays (pass 2)

/// A canvas finger (scripted touches, tests): a thin glass ring tinted by the stress and jamming under it. colour.a is
/// the tint strength; params.z is the tube's half width (m).
fragment float4 toothpasteRingFragment(LabQuadOut in [[stage_in]], constant ToothpasteTankUniforms& t [[buffer(LabFragmentApp)]]) {
    float w = in.params.z;
    float R = in.halfSize.x - w * 2.5;
    float r = length(in.local);
    float d = (r - R) / w;
    float fw = fwidth(d);
    float body = 1.0 - smoothstep(1.0 - fw, 1.0 + fw, abs(d));
    float halo = exp(-max(abs(d) - 1.0, 0.0) * 0.9) * (1.0 - body);
    if (body <= 0.0 && halo < 0.01 && d > 0.0) discard_fragment();
    float2 radial = r > 1e-6 ? in.local / r : float2(1, 0);
    float3 n = normalize(float3(radial * d * 0.95, sqrt(max(1.0 - d * d * 0.9, 0.05))));
    float3 v = float3(0, 0, 1);
    float3 key = normalize(t.keyLight.xyz), fill = normalize(t.fillLight.xyz);
    float NoV = saturate(n.z);
    float F = 0.04 + 0.96 * pow(1.0 - NoV, 5.0);
    float3 tint = in.color.rgb;
    float3 glassC = tint * (0.10 + 0.25 * in.color.a) + toothpasteStudio(reflect(-v, n), toothpasteEnvUp(t)) * F * 1.5;
    glassC += (toothpasteGGX(n, v, key, 0.05) * t.keyLight.w * 2.5 + toothpasteGGX(n, v, fill, 0.08) * t.fillLight.w) * float3(1.0);
    float edgeLine = smoothstep(0.55, 1.0, abs(d)) * body;
    float aBody = body * (0.42 + 0.35 * in.color.a);
    float3 c = glassC * aBody * (1.0 - 0.5 * edgeLine);
    float aHalo = halo * 0.25 * in.color.a;
    c += tint * aHalo * 1.4;
    float alpha = saturate(aBody + aHalo * 0.4 + edgeLine * 0.25);
    float inside = 1.0 - smoothstep(-1.0 - fw, -1.0 + fw, d);
    if (inside > 0.0) {
        float2 s = in.local / max(R, 1e-6);
        float lit = smoothstep(-0.2, 1.0, dot(s, length(key.xy) > 1e-3 ? normalize(key.xy) : float2(0, 1)));
        float aDisc = inside * (0.07 + 0.08 * dot(s, s));
        float3 disc = tint * 0.05 + float3(0.85, 0.92, 1.0) * (0.03 + 0.07 * lit * lit);
        c += disc * aDisc * (1.0 - alpha);
        alpha = saturate(alpha + aDisc * (1.0 - alpha));
    }
    return float4(c, alpha);
}

/// The magnet in the projector's band (MR fluid): a bar magnet (red N, steel-blue S), brighter with the field, its glow
/// rising toward the floor.
fragment float4 toothpasteMagnetFragment(LabQuadOut in [[stage_in]], constant ToothpasteTankUniforms& t [[buffer(LabFragmentApp)]]) {
    float2 l = in.local;
    float2 hs = in.halfSize;
    float2 body = float2(hs.x * 0.82, hs.y * 0.36);
    float sd = labRoundedRectSDF(l - float2(0, -hs.y * 0.35), body, body.y * 0.4);
    float aa = fwidth(sd) * 1.2;
    float a = 1.0 - smoothstep(-aa, aa, sd);
    float field = t.stage.z;
    float glow = exp(-max(sd, 0.0) / (hs.y * 0.35)) * (1.0 - a) * field;
    float3 north = float3(0.62, 0.06, 0.07), south = float3(0.10, 0.20, 0.42);
    float3 base = l.x < 0.0 ? north : south;
    float across = saturate(0.5 + 0.5 * (l.y + hs.y * 0.35) / body.y);
    float3 c = base * (0.45 + 0.55 * across) + float3(0.5) * exp(-pow((across - 0.78) * 9.0, 2.0)) * 0.35;
    c *= 0.6 + 0.4 * field;
    float3 g = float3(0.55, 0.42, 1.0) * glow * 0.4;
    float alpha = saturate(a + glow * 0.3);
    return float4(c * a + g, alpha);
}
