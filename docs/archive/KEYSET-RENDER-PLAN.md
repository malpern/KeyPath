# Keyset Render Plan

This document outlines the research and implementation options for allowing users to customize their virtual keyboard overlay with popular GMK keycap set colorways.

## Top 10 Most Popular GMK Keycap Sets

| Rank | Set | Designer | Key Colors | Why It's Iconic |
|------|-----|----------|------------|-----------------|
| 1 | **GMK Olivia** | Olivia | Black/White base + Rose gold/pink accents | "Arguably the most popular set of all time" - always sold out, $300+ aftermarket |
| 2 | **GMK 8008** | Garrett (Omnitype) | Muted blue + pink accents | "An ICON" - inspired by a sports bra, spawned countless clones |
| 3 | **GMK Laser** | MiTo | Synthwave purple/magenta/cyan | Defined the vaporwave aesthetic in keyboards |
| 4 | **GMK Red Samurai** | RedSuns | Red + dark gray + gold legends | Japanese warrior aesthetic, RedSuns' first set |
| 5 | **GMK Botanical** | Omnitype | White/beige + two-tone green | "Relaxing and pleasing" - nature-inspired colorway |
| 6 | **GMK Bento** | Biip | Light blue + pink + gray + white | Japanese bento box inspired, beloved R2 |
| 7 | **GMK WoB** | GMK | Black + white legends | "The benchmark" - timeless, maximum contrast |
| 8 | **GMK Hyperfuse** | BunnyLake | Gray + cyan + purple | Original "hype" set, defined modern GMK era |
| 9 | **GMK Godspeed** | MiTo | Cream/beige + orange/blue | Apollo 11 inspired, retro space aesthetic |
| 10 | **GMK Dots** | Biip | Various + dot legends | Unique design replacing all letters with circles |

**Honorable mentions:** Blue Samurai, Metropolis, Kaiju, Nautilus, Carbon

---

## Authoritative Sources

### Per-Set Official Sources

| Set | Designer | Official IC Thread | Vendor/Designer Site |
|-----|----------|-------------------|---------------------|
| **Olivia** | Olivia | [GH #94386](https://geekhack.org/index.php?topic=94386.0) | [Oblotzky Industries](https://oblotzky.industries/products/gmk-cyl-olivia-plusplus) |
| **8008** | Garrett (Omnitype) | [GH #100308](https://geekhack.org/index.php?topic=100308.0) | [Omnitype](https://omnitype.com/products/gmk-8008-2-keycap-set) |
| **Laser** | MiTo | Massdrop/Drop threads | [mitormk.com/laser](https://mitormk.com/laser) |
| **Red Samurai** | RedSuns | [GH #89970](https://geekhack.org/index.php?topic=89970.0) | [Drop](https://drop.com/buy/drop-redsuns-gmk-red-samurai-keycap-set) |
| **Botanical** | Omnitype | [GH #102350](https://geekhack.org/index.php?topic=102350.0) | [Omnitype](https://omnitype.com/products/gmk-botanical-2-keycap-set) |
| **Bento** | Biip | [GH #97855](https://geekhack.org/index.php?topic=97855.0) | Various vendors |
| **WoB** | GMK (stock) | N/A (stock set) | [GMK Official](https://www.gmk.net/shop/en/gmk-cyl-wob-white-on-black-keycaps/fptk5009) |
| **Hyperfuse** | BunnyLake | [GH #68198](https://geekhack.org/index.php?topic=68198.0) | [TypeMachina](https://typemachina.com/) |
| **Godspeed** | MiTo | [GH #84090](https://geekhack.org/index.php?topic=84090.0) (SA) | [Drop](https://drop.com/buy/drop-mito-gmk-godspeed-custom-keycap-set) |
| **Dots** | Biip | [GH #100890](https://geekhack.org/index.php?topic=100890.0) | Various vendors |

### Color Code Databases

- [MatrixZJ Color Codes](https://matrixzj.github.io/docs/gmk-keycaps/ColorCodes/) - Hex values + photos
- [Deskthority GMK Colours](https://deskthority.net/wiki/GMK_colours) - Stock codes
- [GMK-Color-List GitHub](https://github.com/eaglenguyen/GMK-Color-List) - 400+ sets organized by color

### Design Resources

- [Open Cherry Font](https://github.com/dakotafelder/open-cherry) - The standard GMK legend font
- [Keyboard Render Kit 2](https://imperfectlink.gumroad.com/l/KRK2) ($45) - 1800+ keycap models for Blender
- [Hackerpilot/KeycapModels](https://github.com/Hackerpilot/KeycapModels) - Free GMK/Cherry Blender models
- [KLE-Render](https://github.com/CQCumbers/kle_render) - Keyboard Layout Editor renderer

---

## The Clone Problem

### How to Ensure Authenticity

**Authoritative Sources (Use These):**
1. **Geekhack IC/GB Threads** - Designer's original posts with official renders
2. **Designer Websites** - mitormk.com, omnitype.com, etc.
3. **Official Vendors** - Drop, NovelKeys, Oblotzky, CannonKeys
4. **MatrixZJ Database** - Catalogs actual GMK sets with photos/specs

**Clone Indicators to Avoid:**
- AliExpress/Taobao product photos (colors are wrong)
- "GMK-style" or "GMK clone" listings
- PBT material (GMK is always ABS)
- Missing/generic packaging in photos
- Slightly off legend alignment

**Key Insight:** Clones typically get colors wrong because they don't have access to GMK's exact RAL/Pantone specs and ABS formulations.

---

## Implementation Options: Basic → Ultra-Realistic

### Overview

| Tier | Approach | Effort | Performance | Fidelity |
|------|----------|--------|-------------|----------|
| 1 | Flat color swap | Days | 120fps | Low |
| 2 | Gradient + lighting hints | 1-2 weeks | 120fps | Medium |
| 3 | Metal shaders (fake 3D) | 2-4 weeks | 60-120fps | High |
| 4 | SceneKit (true 3D) | 1-2 months | 60fps | Very High |
| 5 | RealityKit (PBR) | 2-3 months | 60fps | Photorealistic |

---

### Tier 1: Flat Color Swap (Simplest)

**What it looks like:** Current KeyPath keycaps with GMK colorway applied as solid fills.

**Implementation:**
```swift
struct KeycapColorway {
    let name: String              // "GMK Olivia"
    let baseColor: Color          // #1e1e1e (dark)
    let accentColor: Color        // #e8c4b8 (pink)
    let legendColor: Color        // #e8c4b8
    let modifierColor: Color      // #1e1e1e
}

// Apply to existing OverlayKeycapView
.background(colorway.baseColor)
.foregroundStyle(colorway.legendColor)
```

**Data source:** MatrixZJ hex codes

**Pros:**
- Can ship in a week
- Zero performance impact
- Trivial to add new colorways

**Cons:**
- Doesn't capture the "feel" of GMK
- No depth, no material quality
- Looks like colored rectangles

---

### Tier 2: Gradient + Lighting Hints (SwiftUI Native)

**What it looks like:** Keycaps with subtle gradients simulating Cherry profile curvature and overhead lighting.

**Implementation:**
```swift
struct KeycapView: View {
    let colorway: KeycapColorway

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(
                LinearGradient(
                    colors: [
                        colorway.baseColor.lighter(by: 0.08),  // Top highlight
                        colorway.baseColor,
                        colorway.baseColor.darker(by: 0.05)   // Bottom shadow
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                // Subtle top-edge highlight (simulates light catch)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(colorway.baseColor.lighter(by: 0.15), lineWidth: 0.5)
                    .blur(radius: 0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
    }
}
```

**Enhancements:**
- Per-row gradient adjustment (Cherry profile rows have different heights)
- ABS "sheen" via subtle `.opacity` overlay
- Inner shadow for dish/scoop effect

**Pros:**
- Pure SwiftUI, no Metal knowledge needed
- 120fps on all devices
- Captures ~60% of the GMK aesthetic

**Cons:**
- Still somewhat flat
- Can't do true material effects (subsurface scattering, etc.)

---

### Tier 3: Metal Shaders (Fake 3D, Real Impact)

**What it looks like:** Keycaps with realistic ABS plastic material, proper lighting response, and subtle depth.

**Apple Tech:** SwiftUI Metal Shaders (iOS 17+ / macOS Sonoma+)

**Implementation:**
```metal
// KeycapShader.metal
[[ stitchable ]] half4 keycapMaterial(
    float2 position,
    half4 color,
    float2 size,
    float row,           // Cherry profile row (1-4)
    float3 lightDir,     // Simulated light direction
    float glossiness     // ABS vs matte finish
) {
    // Calculate surface normal from Cherry profile curve
    float2 uv = position / size;
    float curve = cherryProfileCurve(uv, row);
    float3 normal = calculateNormal(uv, curve);

    // Diffuse lighting
    float diffuse = max(dot(normal, lightDir), 0.0);

    // Specular highlight (ABS plastic sheen)
    float3 viewDir = float3(0, 0, 1);
    float3 halfVec = normalize(lightDir + viewDir);
    float specular = pow(max(dot(normal, halfVec), 0.0), glossiness * 32.0);

    // Combine
    half3 result = color.rgb * (0.3 + 0.7 * diffuse) + specular * 0.15;
    return half4(result, color.a);
}
```

```swift
// SwiftUI usage
OverlayKeycapView()
    .layerEffect(
        ShaderLibrary.keycapMaterial(
            .float2(size),
            .float(row),
            .float3(lightDirection),
            .float(glossiness)
        ),
        maxSampleOffset: .zero
    )
```

**Resources:**
- [Inferno shader library](https://github.com/twostraws/Inferno) - Starting point for Metal + SwiftUI
- [WWDC24: Create custom visual effects](https://developer.apple.com/videos/play/wwdc2024/10151/)
- [Jacob Bartlett's Metal tutorial](https://blog.jacobstechtavern.com/p/metal-in-swiftui-how-to-write-shaders)

**Pros:**
- Hardware accelerated (60-120fps)
- Can achieve convincing ABS plastic look
- Stays in 2D rendering pipeline (efficient)
- Single shader file, ~100 lines

**Cons:**
- Requires Metal Shading Language knowledge
- Still not "true" 3D
- Complex effects (legends, novelties) need more work

---

### Tier 4: SceneKit (True 3D, Moderate Effort)

**What it looks like:** Actual 3D keycap models with proper geometry, materials, and lighting.

**Apple Tech:** SceneKit + SwiftUI

**Implementation:**
```swift
struct Keycap3DView: NSViewRepresentable {
    let colorway: KeycapColorway
    let row: Int  // Cherry profile row

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = createScene()
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = .clear
        return scnView
    }

    func createScene() -> SCNScene {
        let scene = SCNScene()

        // Load keycap model (from KRK2 or Hackerpilot)
        let keycap = SCNScene(named: "cherry_r\(row).usdz")!.rootNode

        // Apply GMK material
        let material = SCNMaterial()
        material.diffuse.contents = NSColor(colorway.baseColor)
        material.specular.contents = NSColor.white
        material.shininess = 0.3  // ABS plastic
        material.roughness.contents = 0.4
        keycap.geometry?.materials = [material]

        scene.rootNode.addChildNode(keycap)
        return scene
    }
}
```

**3D Model Sources:**
- [Hackerpilot/KeycapModels](https://github.com/Hackerpilot/KeycapModels) - Free GMK/Cherry Blender models
- [Keyboard Render Kit 2](https://imperfectlink.gumroad.com/l/KRK2) ($45) - 1800+ keycap models
- Convert Blender → USDZ for Apple compatibility

**Pros:**
- Photorealistic potential
- Proper Cherry profile geometry
- Can rotate/animate keys
- Industry-standard approach

**Cons:**
- 100+ keycap models to manage
- Memory overhead (~50-100MB for full keyboard)
- 60fps ceiling, potential hitches
- Complexity explosion with legends/novelties

---

### Tier 5: RealityKit (PBR, Maximum Fidelity)

**What it looks like:** Indistinguishable from professional keycap renders (like KRK2 output).

**Apple Tech:** RealityKit 4 + Model3D (macOS 15+)

**Why RealityKit over SceneKit:**
- **PBR (Physically Based Rendering)** - Same material model as Blender Cycles
- **MaterialX support** - Industry-standard material definitions
- **Metal integration** - Direct GPU access for custom effects
- **Cross-platform** - Same code for macOS, iOS, visionOS

**Implementation:**
```swift
import RealityKit

struct KeyboardRealityView: View {
    let colorway: KeycapColorway

    var body: some View {
        RealityView { content in
            // Load pre-baked keyboard model
            let keyboard = try! await Entity.load(named: "keyboard_tkl.usdz")

            // Apply colorway materials dynamically
            keyboard.applyColorway(colorway)

            // Add studio lighting
            let light = DirectionalLight()
            light.light.intensity = 1000
            content.add(light)

            content.add(keyboard)
        }
        .realityViewCameraContent(.virtual)  // Non-AR mode
    }
}

extension Entity {
    func applyColorway(_ colorway: KeycapColorway) {
        // Traverse keycap entities and swap materials
        for keycap in self.findEntities(named: "keycap_*") {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: colorway.baseColor.cgColor)
            material.roughness = 0.4
            material.metallic = 0.0
            keycap.model?.materials = [material]
        }
    }
}
```

**Asset Pipeline:**
1. Export KRK2 models → USDZ (Apple's 3D format)
2. Define material slots per keycap type (alpha, modifier, accent, novelty)
3. Runtime material swap based on colorway selection

**Pros:**
- Maximum visual fidelity
- Future-proof (visionOS ready)
- Apple's strategic direction for 3D

**Cons:**
- macOS 15+ only (Sequoia)
- Heaviest implementation
- Complex asset pipeline
- Overkill for an overlay?

---

## Recommendation: Tier 2 → Tier 3 Migration Path

### Phase 1: Ship Tier 2 (2-3 weeks)
- Implement gradient-based keycaps with colorway system
- Add the top 10 GMK colorways from MatrixZJ data
- Validate user interest before deeper investment

### Phase 2: Upgrade to Tier 3 (if demand exists)
- Write Metal shader for ABS plastic material
- Same colorway data, much richer visual
- Stays performant for overlay use case

### Why not Tier 4/5?
- KeyPath's overlay is **utility-focused**, not a render showcase
- 3D adds complexity without proportional UX benefit
- Battery/performance concerns for always-visible overlay
- SceneKit/RealityKit better suited for a "keycap preview" feature, not live overlay

---

## Data Model

```swift
struct GMKColorway: Codable, Identifiable {
    let id: String           // "olivia"
    let displayName: String  // "GMK Olivia"
    let designer: String     // "Olivia"
    let year: Int            // 2018

    // Core colors (from MatrixZJ)
    let alphaBase: String    // Hex "#1e1e1e"
    let alphaLegend: String  // Hex "#e8c4b8"
    let modBase: String
    let modLegend: String
    let accentBase: String
    let accentLegend: String

    // Optional: full GMK color codes for accuracy
    let gmkCodes: [String: String]?  // ["CR": "#1e1e1e", "custom": "#e8c4b8"]

    // Attribution
    let sourceURL: URL?      // Geekhack IC thread
    let vendorURL: URL?      // Official vendor
}
```

---

## Next Steps

1. **Extract colorway data** - Pull hex codes for all 10 sets from MatrixZJ
2. **Prototype Tier 2** - Quick gradient-based implementation in current overlay
3. **Research Metal shaders** - Spike on ABS plastic material shader
4. **Consider designer outreach** - Get blessing from designers for colorway use

---

## References

- [Hacking with Swift - Metal Shaders in SwiftUI](https://www.hackingwithswift.com/quick-start/swiftui/how-to-add-metal-shaders-to-swiftui-views-using-layer-effects)
- [WWDC24 - Create custom visual effects with SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10151/)
- [WWDC24 - Discover RealityKit APIs](https://developer.apple.com/videos/play/wwdc2024/10103/)
- [GMK Official Design Guidelines](https://www.gmk.net/fileadmin/user_upload/faq/Guidelines_for_Custom_GMK_Keycap_Set_14.pdf)
- [Keyboards Expert - How to Spot GMK Clones](https://keyboardsexpert.com/how-to-spot-gmk-keycap-clones/)
