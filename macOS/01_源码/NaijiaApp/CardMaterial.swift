import AppKit
import SwiftUI

struct CardMotionConfig: Decodable {
    struct Layer: Decodable { let speed, direction, parallax, opacity: Double; let count: Int }
    let version: Int
    let cardId, style, materialMask, backgroundMask: String
    let tiltDegrees, returnSeconds, fps, foilOpacity, sparklePeriod: Double
    let sparkleCount: Int
    let metalContrast, specularStrength, glintStrength, portalDepth: Double?
    let portalScaleSpan, portalDrift, portalNearSize: Double?
    let starTexture: String?
    let gemCount: Int?
    let gemStrength, skyRotation: Double?
    let layers: [Layer]
}

struct CardMotionFace: View, Animatable {
    let image: NSImage?
    let config: CardMotionConfig?
    let material, background: NSImage?
    let time: Double
    nonisolated var x, y: Double
    let enabled: Bool
    var skyTexture: NSImage? = nil
    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(x, y) }
        set { x = newValue.first; y = newValue.second }
    }
    var body: some View {
        ZStack {
            if let image { Image(nsImage: image).resizable().interpolation(.none) }
            if enabled, let config, let material, let background {
                if config.style == "黑金卡" {
                    metal(config).mask(Image(nsImage: material).resizable().interpolation(.none))
                } else {
                    foil(config).mask(Image(nsImage: material).resizable().interpolation(.none))
                }
                if config.style == "幻影卡" {
                    if let skyTexture, config.starTexture != nil {
                        crystalSky(config, texture: skyTexture).mask(Image(nsImage: background).resizable().interpolation(.none))
                    } else {
                        stars(config).mask(Image(nsImage: background).resizable().interpolation(.none))
                    }
                } else if config.style == "闪光卡" {
                    sparkles(config).mask(Image(nsImage: material).resizable().interpolation(.none))
                }
            }
        }.frame(width: 288, height: 432).clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private func foil(_ c: CardMotionConfig) -> some View {
        Canvas { ctx, size in
            let colors: [Color] = c.style == "黑金卡" ? [.clear, .yellow.opacity(0.15), Color(red: 1, green: 0.92, blue: 0.65), .clear] : [.clear, .cyan.opacity(0.4), .pink.opacity(0.6), .white.opacity(0.7), .purple.opacity(0.35), .clear]
            let center = CGPoint(x: size.width * (0.5 + x * 0.40), y: size.height * (0.5 + y * 0.30))
            let gradient = GraphicsContext.Shading.linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: center.x - 150, y: center.y - 210 - x * 60), endPoint: CGPoint(x: center.x + 150, y: center.y + 210 + x * 60))
            ctx.opacity = c.foilOpacity * (0.3 + min(1, abs(x) + abs(y)) * 0.7)
            ctx.blendMode = .screen
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: gradient)
            ctx.opacity *= 0.7
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 65, y: center.y - 100, width: 130, height: 200)), with: .radialGradient(Gradient(colors: [.white.opacity(0.7), .clear]), center: center, startRadius: 0, endRadius: 105))
        }
    }
    private func crystalSky(_ c: CardMotionConfig, texture: NSImage) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { depth in
                let layer = c.layers[depth]
                let baseSide = 720.0 - Double(depth) * 72
                Image(nsImage: texture).resizable().interpolation(.none)
                    .frame(width: baseSide, height: baseSide)
                    .rotationEffect(.radians(time * (c.skyRotation ?? 0.10) * (depth == 1 ? -0.72 : (depth == 2 ? 1.5 : 1))))
                    .offset(x: x * 288 * layer.parallax + sin(time * 0.10 + Double(depth)) * 14,
                            y: y * 432 * layer.parallax + cos(time * 0.08 + Double(depth)) * 12)
                    .saturation(depth == 0 ? 1.22 : 1.45)
                    .contrast(1.16)
                    .brightness(depth == 0 ? -0.08 : 0)
                    .hueRotation(.degrees(depth == 2 ? 18 : 0))
                    .opacity(depth == 0 ? 1 : (depth == 1 ? 0.32 : 0.20))
                    .blendMode(depth == 0 ? .normal : .screen)
            }
            Canvas { ctx, size in drawCrystals(&ctx, size: size, config: c) }
        }.frame(width: 288, height: 432).clipped()
    }
    private func drawCrystals(_ ctx: inout GraphicsContext, size: CGSize, config c: CardMotionConfig) {
        let colors: [Color] = [.cyan, Color(red: 0.78, green: 0.36, blue: 1), Color(red: 1, green: 0.36, blue: 0.80)]
        for depth in 0..<3 {
            let layer = c.layers[depth]
            let angle = time * layer.speed * layer.direction
            let ca = cos(angle), sa = sin(angle)
            let count = max(1, (c.gemCount ?? 26) / 3)
            for i in 0..<count {
                let seed = Double(i * 67 + depth * 43)
                let u = Double((i * 193 + depth * 137) % 719) / 719 - 0.5
                let v = Double((i * 311 + depth * 83) % 727) / 727 - 0.5
                let px = u * size.width * 1.65
                let py = v * size.height * 1.50
                let posX = size.width * 0.5 + px * ca - py * sa + x * size.width * layer.parallax
                let posY = size.height * 0.5 + px * sa + py * ca + y * size.height * layer.parallax
                let p = CGPoint(x: posX, y: posY)
                let radius = 7.0 + Double(depth) * 3.0 + Double(i % 3) * 1.8
                let tilt = angle * 0.6 + seed
                let axisX = CGPoint(x: cos(tilt) * radius * 0.64, y: sin(tilt) * radius * 0.64)
                let axisY = CGPoint(x: -sin(tilt) * radius * 1.5, y: cos(tilt) * radius * 1.5)
                let vertices = [CGPoint(x:p.x+axisY.x,y:p.y+axisY.y),CGPoint(x:p.x+axisX.x,y:p.y+axisX.y),CGPoint(x:p.x-axisY.x,y:p.y-axisY.y),CGPoint(x:p.x-axisX.x,y:p.y-axisX.y)]
                let light = 0.48 + 0.52 * pow(max(0, sin(time * 0.85 + seed)), 6)
                let strength = c.gemStrength ?? 0.92
                ctx.blendMode = .screen
                for face in 0..<4 {
                    var triangle = Path(); triangle.move(to:p);triangle.addLine(to:vertices[face]);triangle.addLine(to:vertices[(face+1)%4]);triangle.closeSubpath()
                    ctx.opacity = strength * light * (face % 2 == 0 ? 0.90 : 0.40)
                    ctx.fill(triangle, with:.color(face == 0 ? .white : colors[(depth+face)%3]))
                }
                ctx.opacity = strength * light * 0.90
                var edge=Path();edge.move(to:vertices[0]);for point in vertices.dropFirst(){edge.addLine(to:point)};edge.closeSubpath()
                ctx.stroke(edge,with:.color(.white),lineWidth:0.55)
                // Narrow diffraction spikes track the same rotating field, not a full-card sweep.
                let flash = pow(max(0,sin(time * 0.95 + seed + 1.4)),12)
                if flash > 0.02 {
                    ctx.opacity = flash * strength
                    var star=Path();star.move(to:CGPoint(x:p.x-radius*2.4,y:p.y));star.addLine(to:CGPoint(x:p.x+radius*2.4,y:p.y));star.move(to:CGPoint(x:p.x,y:p.y-radius*3));star.addLine(to:CGPoint(x:p.x,y:p.y+radius*3))
                    ctx.stroke(star,with:.color(.white),lineWidth:0.75)
                    ctx.opacity *= 0.35
                    ctx.fill(Path(ellipseIn:CGRect(x:p.x-18,y:p.y-18,width:36,height:36)),with:.radialGradient(Gradient(colors:[colors[depth],.clear]),center:p,startRadius:0,endRadius:18))
                }
            }
            for i in 0..<layer.count {
                let u=Double((i*73+depth*71)%997)/997-0.5
                let v=Double((i*193+depth*97)%991)/991-0.5
                let px=u*size.width*1.7, py=v*size.height*1.6
                let starX: Double = size.width * 0.5 + px * ca - py * sa + x * size.width * layer.parallax
                let starY: Double = size.height * 0.5 + px * sa + py * ca + y * size.height * layer.parallax
                let p = CGPoint(x: starX, y: starY)
                ctx.opacity=layer.opacity*0.7
                let side=0.6+Double(depth)*0.4
                ctx.fill(Path(CGRect(x:p.x,y:p.y,width:side,height:side)),with:.color(i%7==0 ? .white : colors[depth]))
            }
        }
    }

    private func stars(_ c: CardMotionConfig) -> some View {
        Canvas { ctx, size in drawStars(&ctx, size: size, config: c) }
    }
    private func drawStars(_ ctx: inout GraphicsContext, size: CGSize, config c: CardMotionConfig) {
        let bounds = CGRect(origin: .zero, size: size)
        // The dark optical bed exists only in original background pixels, never on the frame or subject.
        ctx.opacity = c.portalDepth ?? 0.48
        ctx.fill(Path(bounds), with: .color(Color(red: 0.015, green: 0.018, blue: 0.10)))
        let colors: [Color] = [Color(red: 0.32, green: 0.40, blue: 1), Color(red: 0.20, green: 0.86, blue: 1), Color(red: 0.94, green: 0.30, blue: 0.90)]
        for (depth, layer) in c.layers.enumerated() {
            let angle = time * layer.speed * layer.direction
            let ca = cos(angle), sa = sin(angle)
            let breathing = 1 + sin(time * (0.16 + Double(depth) * 0.035) + Double(depth) * 2.1) * (c.portalScaleSpan ?? 0.09)
            let travelX = sin(time * layer.speed * 0.65 + Double(depth)) * size.width * (c.portalDrift ?? 0.06)
            let travelY = cos(time * layer.speed * 0.8 + Double(depth) * 2) * size.height * (c.portalDrift ?? 0.06) * 0.65
            for i in 0..<layer.count {
                // Each depth is a separate, moving star plane. The stable seed avoids flicker.
                let u = Double((i * 73 + depth * 43) % 997) / 997 - 0.5
                let v = Double((i * 193 + depth * 137) % 991) / 991 - 0.5
                let px = u * size.width * 1.65
                let py = v * size.height * 1.4
                let posX = size.width * 0.5 + (px * ca - py * sa) * breathing + travelX + x * size.width * layer.parallax
                let posY = size.height * 0.56 + (px * sa + py * ca) * breathing + travelY + y * size.height * layer.parallax
                let p = CGPoint(x: posX, y: posY)
                let color = colors[depth]
                let sizeVariation = Double((i * 17) % 7) / 7
                let sizeByDepth: [Double] = [0.7, 1.65, c.portalNearSize ?? 2.0]
                let side = (sizeByDepth[depth] + sizeVariation * Double(depth + 1) * 0.55) * breathing
                ctx.blendMode = .screen
                ctx.opacity = layer.opacity * (0.45 + sizeVariation * 0.55)
                ctx.fill(Path(CGRect(x: p.x, y: p.y, width: side, height: side)), with: .color(i % 13 == 0 ? .white : color))
                // Large foreground flecks have a colored optical fringe, not a flashing star flare.
                if depth == 2 && i % 3 == 0 {
                    ctx.opacity = layer.opacity * 0.42
                    let fringe = CGRect(x: p.x - side * 0.5, y: p.y + side * 0.32, width: side * 2, height: max(1, side * 0.32))
                    ctx.fill(Path(fringe), with: .color(.cyan))
                }
                if i % 9 == 0 {
                    let radius = 10.0 + Double(depth) * 6
                    ctx.opacity = layer.opacity * 0.42
                    let rect = CGRect(x: p.x-radius, y: p.y-radius, width: radius*2, height: radius*2)
                    ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [color, .clear]), center: p, startRadius: 0, endRadius: radius))
                }
            }
            // Low-opacity colored reflection patches drift independently beneath the stars.
            for i in 0..<3 {
                let phase = Double(i) * 2.1 + Double(depth)
                let cx = size.width * (0.5 + cos(angle + phase) * 0.30) + x * 12 * Double(depth + 1)
                let cy = size.height * (0.54 + sin(angle * 0.7 + phase) * 0.27)
                let center = CGPoint(x: cx, y: cy)
                ctx.opacity = layer.opacity * 0.30
                ctx.fill(Path(ellipseIn: CGRect(x: cx-65, y: cy-80, width: 130, height: 160)), with: .radialGradient(Gradient(colors: [colors[depth], .clear]), center: center, startRadius: 0, endRadius: 85))
            }
        }
    }
    private func metal(_ c: CardMotionConfig) -> some View {
        Canvas { ctx, size in drawMetal(&ctx, size: size, config: c) }
    }
    private func drawMetal(_ ctx: inout GraphicsContext, size: CGSize, config c: CardMotionConfig) {
            let center = CGPoint(x: size.width * (0.50 + x * 0.42), y: size.height * (0.48 + y * 0.30))
            let angle = -0.6 + x * 0.55 + y * 0.25
            let axis = CGPoint(x: cos(angle) * 230, y: sin(angle) * 230)
            let start = CGPoint(x: center.x - axis.x, y: center.y - axis.y)
            let end = CGPoint(x: center.x + axis.x, y: center.y + axis.y)
            let area = Path(CGRect(origin: .zero, size: size))
            // Alternating bronze shadow and tight champagne highlights produce a polished metal response.
            ctx.blendMode = .multiply
            ctx.opacity = c.metalContrast ?? 0.60
            let shadow = Gradient(stops: [.init(color: .white, location: 0), .init(color: Color(red: 0.24, green: 0.12, blue: 0.015), location: 0.29), .init(color: .white, location: 0.44), .init(color: .white, location: 0.56), .init(color: Color(red: 0.45, green: 0.22, blue: 0.035), location: 0.70), .init(color: .white, location: 1)])
            ctx.fill(area, with: .linearGradient(shadow, startPoint: start, endPoint: end))
            ctx.blendMode = .screen
            ctx.opacity = c.specularStrength ?? 0.94
            let specular = Gradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.32), .init(color: Color(red: 1, green: 0.68, blue: 0.18).opacity(0.25), location: 0.42), .init(color: Color(red: 1, green: 0.92, blue: 0.65).opacity(0.70), location: 0.478), .init(color: .white, location: 0.50), .init(color: Color(red: 1, green: 0.97, blue: 0.83), location: 0.515), .init(color: .clear, location: 0.55), .init(color: Color(red: 1, green: 0.72, blue: 0.27).opacity(0.35), location: 0.72), .init(color: .clear, location: 0.82), .init(color: .clear, location: 1)])
            ctx.fill(area, with: .linearGradient(specular, startPoint: start, endPoint: end))
            for i in 0..<4 {
                let phase = time * 0.38 + Double(i) * 1.57 + x * 0.8 - y * 0.5
                let p = CGPoint(x: size.width * (0.5 + cos(phase) * 0.40), y: size.height * (0.57 + sin(phase) * 0.32))
                ctx.opacity = (c.glintStrength ?? 0.80) * (0.60 + 0.4 * abs(x))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x-18, y: p.y-18, width: 36, height: 36)), with: .radialGradient(Gradient(colors: [.white, .yellow.opacity(0.4), .clear]), center: p, startRadius: 0, endRadius: 18))
            }
    }
    private func sparkles(_ c: CardMotionConfig) -> some View {
        Canvas { ctx, size in
            for i in 0..<c.sparkleCount {
                let cycle = (time + Double(i) * 1.37).truncatingRemainder(dividingBy: c.sparklePeriod)
                let brightness = max(0, 1 - abs(cycle - 0.35) / 0.35)
                let p = CGPoint(x: size.width * (i % 2 == 0 ? 0.10 : 0.90), y: size.height * (0.26 + Double(i / 2) * 0.26))
                ctx.opacity = brightness * 0.65
                let s = 1.4
                ctx.fill(Path(CGRect(x: p.x - s, y: p.y - 3*s, width: 2*s, height: 6*s)), with: .color(.white))
                ctx.fill(Path(CGRect(x: p.x - 3*s, y: p.y - s, width: 6*s, height: 2*s)), with: .color(.white))
            }
        }
    }
}
