import Cocoa

/// Draws Mochi (a round little cream-puff creature with a sprout on its head) plus its speech bubble.
final class PetView: NSView {
    enum Mood { case walking, idle, sitting, sleeping, excited }

    var mood: Mood = .idle
    var facingRight = true
    var walkPhase: CGFloat = 0

    // animation state
    private var time: CGFloat = 0
    private var blinkCountdown: CGFloat = 3
    private var blink: CGFloat = 0          // 0 = open, 1 = closed
    private var jumpY: CGFloat = 0
    private var jumpVel: CGFloat = 0
    private var sparkleTime: CGFloat = 0
    private var heartTime: CGFloat = 0
    private var happyTime: CGFloat = 0
    private var ringTime: CGFloat = 0       // wiggle while a bubble is fresh

    // bubble state
    private(set) var bubble: BubbleMessage?
    private var bubbleAlpha: CGFloat = 0
    private var bubbleClosing = false
    private(set) var bubbleRect: NSRect = .zero
    /// Horizontal range of this view that is actually on screen (window may hang off the edge).
    var visibleRange: ClosedRange<CGFloat> = 0...320

    var onPetClick: (() -> Void)?
    var onBubbleClick: (() -> Void)?
    var onBubbleGone: (() -> Void)?

    let groundY: CGFloat = 6

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var petRect: NSRect {
        NSRect(x: bounds.midX - 50, y: 0, width: 100, height: 96 + jumpY)
    }

    var isAirborne: Bool { jumpY > 0 || jumpVel != 0 }

    // MARK: Public actions

    func hop(sparkles: Bool = true) {
        if !isAirborne { jumpVel = 230 }
        if sparkles { sparkleTime = 1.4 }
        happyTime = 2.2
    }

    func pet() {
        hop(sparkles: false)
        heartTime = 1.8
    }

    func showBubble(_ b: BubbleMessage) {
        bubble = b
        bubbleClosing = false
        bubbleAlpha = 0
        ringTime = 1.2
    }

    func closeBubble() {
        guard bubble != nil else { return }
        bubbleClosing = true
    }

    // MARK: Animation

    func update(dt: CGFloat) {
        time += dt

        // blinking
        blinkCountdown -= dt
        if blinkCountdown <= 0 {
            blink = 1
            blinkCountdown = CGFloat.random(in: 2.5...5.5)
        }
        blink = max(0, blink - dt * 7)

        // jumping
        if isAirborne {
            jumpVel -= 900 * dt
            jumpY += jumpVel * dt
            if jumpY <= 0 { jumpY = 0; jumpVel = 0 }
        }

        sparkleTime = max(0, sparkleTime - dt)
        heartTime = max(0, heartTime - dt)
        happyTime = max(0, happyTime - dt)
        ringTime = max(0, ringTime - dt)

        // bubble fade
        if bubble != nil {
            let target: CGFloat = bubbleClosing ? 0 : 1
            bubbleAlpha += (target - bubbleAlpha) * min(1, dt * 10)
            if bubbleClosing && bubbleAlpha < 0.03 {
                bubble = nil
                bubbleClosing = false
                bubbleAlpha = 0
                bubbleRect = .zero
                onBubbleGone?()
            }
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if bubble != nil, bubbleRect.contains(p) {
            onBubbleClick?()
        } else if petRect.contains(p) {
            onPetClick?()
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        bounds.fill(using: .copy)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawPet(ctx)
        drawEffects()
        if bubble != nil && bubbleAlpha > 0.01 { drawBubble(ctx) }
    }

    // Palette
    private let outline = NSColor(hex: 0x7A5A48)
    private let bodyTop = NSColor(hex: 0xFFF8EE)
    private let bodyBottom = NSColor(hex: 0xFFE1C2)
    private let earPink = NSColor(hex: 0xFFB3C1)
    private let blushPink = NSColor(hex: 0xFF8FA3, alpha: 0.55)
    private let eyeDark = NSColor(hex: 0x3B2C35)
    private let leafGreen = NSColor(hex: 0x8FD48A)
    private let leafLine = NSColor(hex: 0x4E9A4A)

    private var tucked: Bool { mood == .sitting || mood == .sleeping }
    private var isHappy: Bool { happyTime > 0 || mood == .excited }

    private func drawPet(_ ctx: CGContext) {
        let cx = bounds.midX
        let walking = mood == .walking && !isAirborne
        let bob: CGFloat
        if walking { bob = abs(sin(walkPhase)) * 3.5 }
        else if mood == .sleeping { bob = sin(time * 1.5) * 1.2 }
        else { bob = sin(time * 2.2) * 0.9 }

        // shadow
        let s = max(0.45, 1 - jumpY / 140)
        NSColor(white: 0, alpha: 0.14 * s).setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - 29 * s, y: groundY - 4, width: 58 * s, height: 8)).fill()

        ctx.saveGState()
        ctx.translateBy(x: cx, y: groundY + bob + jumpY)
        if !facingRight { ctx.scaleBy(x: -1, y: 1) }

        // squash & stretch
        var sx: CGFloat = 1, sy: CGFloat = 1
        if isAirborne { sy = 1 + min(0.10, abs(jumpVel) / 2600); sx = 1 / sy }
        if tucked { sy *= 0.93; sx *= 1.04 }
        if ringTime > 0 {   // excited wiggle when a message pops up
            let w = sin(time * 40) * 0.035 * ringTime
            ctx.rotate(by: w)
        }
        ctx.scaleBy(x: sx, y: sy)

        drawTail()
        if !tucked { drawFeet(walking: walking) }
        drawEar(side: -1)
        drawEar(side: 1)
        drawBody()
        drawSprout(ctx)
        drawFace()
        ctx.restoreGState()
    }

    private func drawTail() {
        let speed: CGFloat = mood == .walking ? 7 : 3
        let w = sin(time * speed) * 4
        let p = NSBezierPath()
        p.move(to: NSPoint(x: -27, y: 14))
        p.curve(to: NSPoint(x: -43, y: 33 + w),
                controlPoint1: NSPoint(x: -42, y: 9),
                controlPoint2: NSPoint(x: -50, y: 24 + w * 0.5))
        p.lineCapStyle = .round
        p.lineWidth = 10
        outline.setStroke(); p.stroke()
        p.lineWidth = 6
        bodyBottom.setStroke(); p.stroke()
    }

    private func drawFeet(walking: Bool) {
        let s = walking ? sin(walkPhase) : 0
        let feet: [(CGFloat, CGFloat)] = [(-12 - s * 5, 2 + max(0, -s) * 3),
                                          (12 + s * 5, 2 + max(0, s) * 3)]
        for (x, y) in feet {
            let r = NSBezierPath(ovalIn: NSRect(x: x - 8, y: y - 3, width: 16, height: 10))
            NSColor(hex: 0xFFE6CC).setFill(); r.fill()
            outline.setStroke(); r.lineWidth = 2; r.stroke()
        }
    }

    private func drawEar(side s: CGFloat) {
        let twitch = (mood == .excited || ringTime > 0) ? sin(time * 18) * 2 : 0
        let ear = NSBezierPath()
        ear.move(to: NSPoint(x: s * 28, y: 42))
        ear.line(to: NSPoint(x: s * 22 + twitch * s, y: 67))
        ear.line(to: NSPoint(x: s * 6, y: 55))
        ear.close()
        ear.lineJoinStyle = .round
        ear.lineWidth = 2.2
        bodyTop.setFill(); ear.fill()
        outline.setStroke(); ear.stroke()

        let inner = NSBezierPath()
        inner.move(to: NSPoint(x: s * 24, y: 48))
        inner.line(to: NSPoint(x: s * 21 + twitch * s * 0.7, y: 61))
        inner.line(to: NSPoint(x: s * 12, y: 54))
        inner.close()
        inner.lineJoinStyle = .round
        earPink.setFill(); inner.fill()
    }

    private func drawBody() {
        let rect = NSRect(x: -33, y: 3, width: 66, height: 56)
        let body = NSBezierPath(roundedRect: rect, xRadius: 31, yRadius: 27)
        NSGradient(starting: bodyBottom, ending: bodyTop)?.draw(in: body, angle: 90)
        outline.setStroke()
        body.lineWidth = 2.2
        body.stroke()

        // soft belly + shine
        NSColor(white: 1, alpha: 0.45).setFill()
        NSBezierPath(ovalIn: NSRect(x: -17, y: 7, width: 34, height: 20)).fill()
        NSColor(white: 1, alpha: 0.7).setFill()
        NSBezierPath(ovalIn: NSRect(x: -24, y: 44, width: 10, height: 6)).fill()
    }

    private func drawSprout(_ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 1, y: 57)
        let sway = sin(time * 2.4) * 0.16 + (mood == .walking ? sin(walkPhase) * 0.08 : 0)
        ctx.rotate(by: sway)

        let stem = NSBezierPath()
        stem.move(to: .zero)
        stem.curve(to: NSPoint(x: 0, y: 12), controlPoint1: NSPoint(x: 2, y: 4), controlPoint2: NSPoint(x: -1, y: 8))
        stem.lineWidth = 2.6
        stem.lineCapStyle = .round
        leafLine.setStroke(); stem.stroke()

        for side in [-1.0, 1.0] as [CGFloat] {
            let size: CGFloat = side > 0 ? 1.1 : 0.95
            let leaf = NSBezierPath()
            leaf.move(to: NSPoint(x: 0, y: 12))
            leaf.curve(to: NSPoint(x: side * 12 * size, y: 17 * size),
                       controlPoint1: NSPoint(x: side * 3, y: 20 * size),
                       controlPoint2: NSPoint(x: side * 10 * size, y: 21 * size))
            leaf.curve(to: NSPoint(x: 0, y: 12),
                       controlPoint1: NSPoint(x: side * 10 * size, y: 11),
                       controlPoint2: NSPoint(x: side * 4, y: 9))
            leafGreen.setFill(); leaf.fill()
            leafLine.setStroke(); leaf.lineWidth = 1.5; leaf.stroke()
        }
        ctx.restoreGState()
    }

    private func drawFace() {
        let fx: CGFloat = 6     // face looks toward walking direction
        let ey: CGFloat = 33

        // blush
        blushPink.setFill()
        NSBezierPath(ovalIn: NSRect(x: fx - 24, y: 22, width: 11, height: 6.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: fx + 13, y: 22, width: 11, height: 6.5)).fill()

        eyeDark.setStroke()
        eyeDark.setFill()
        for ex in [fx - 11, fx + 11] {
            if mood == .sleeping {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: ex - 4.5, y: ey + 1))
                p.curve(to: NSPoint(x: ex + 4.5, y: ey + 1),
                        controlPoint1: NSPoint(x: ex - 3, y: ey - 3), controlPoint2: NSPoint(x: ex + 3, y: ey - 3))
                p.lineWidth = 2.2; p.lineCapStyle = .round; p.stroke()
            } else if isHappy {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: ex - 4.5, y: ey - 2))
                p.line(to: NSPoint(x: ex, y: ey + 3))
                p.line(to: NSPoint(x: ex + 4.5, y: ey - 2))
                p.lineWidth = 2.5; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
            } else {
                let h = max(1.8, 13 * (1 - blink))
                NSBezierPath(ovalIn: NSRect(x: ex - 4.8, y: ey - h / 2, width: 9.6, height: h)).fill()
                if blink < 0.4 {
                    NSColor.white.setFill()
                    NSBezierPath(ovalIn: NSRect(x: ex - 2.6, y: ey + 0.8, width: 4.4, height: 4.4)).fill()
                    NSBezierPath(ovalIn: NSRect(x: ex + 1.2, y: ey - 3.6, width: 2, height: 2)).fill()
                    eyeDark.setFill()
                }
            }
        }

        // mouth
        let mx = fx, my: CGFloat = 27
        if isHappy {
            let m = NSBezierPath()
            m.move(to: NSPoint(x: mx - 4.5, y: my))
            m.curve(to: NSPoint(x: mx + 4.5, y: my),
                    controlPoint1: NSPoint(x: mx - 3.5, y: my - 7), controlPoint2: NSPoint(x: mx + 3.5, y: my - 7))
            m.close()
            NSColor(hex: 0xFF7A8A).setFill(); m.fill()
            eyeDark.setStroke(); m.lineWidth = 1.5; m.lineJoinStyle = .round; m.stroke()
        } else if mood == .sleeping {
            let m = NSBezierPath(ovalIn: NSRect(x: mx - 1.8, y: my - 3, width: 3.6, height: 3.2))
            eyeDark.setStroke(); m.lineWidth = 1.3; m.stroke()
        } else {
            let m = NSBezierPath()
            m.move(to: NSPoint(x: mx - 5, y: my))
            m.curve(to: NSPoint(x: mx, y: my), controlPoint1: NSPoint(x: mx - 5, y: my - 3.8), controlPoint2: NSPoint(x: mx, y: my - 3.8))
            m.curve(to: NSPoint(x: mx + 5, y: my), controlPoint1: NSPoint(x: mx, y: my - 3.8), controlPoint2: NSPoint(x: mx + 5, y: my - 3.8))
            m.lineWidth = 1.6; m.lineCapStyle = .round
            eyeDark.setStroke(); m.stroke()
        }
    }

    // Zzz, sparkles, hearts — drawn in view space (not mirrored)
    private func drawEffects() {
        let cx = bounds.midX
        let top = groundY + 66 + jumpY

        if mood == .sleeping {
            for i in 0..<3 {
                var ph = (time * 0.35 + CGFloat(i) / 3).truncatingRemainder(dividingBy: 1)
                if ph < 0 { ph += 1 }
                let a = sin(ph * .pi)
                let font = NSFont.systemFont(ofSize: 9 + ph * 9, weight: .heavy)
                let str = NSAttributedString(string: "z", attributes: [.font: font,
                                                                       .foregroundColor: NSColor(hex: 0x9A8FD0, alpha: a)])
                let dir: CGFloat = facingRight ? 1 : -1
                str.draw(at: NSPoint(x: cx + dir * (18 + ph * 16) - 4, y: top - 8 + ph * 34))
            }
        }

        if sparkleTime > 0 {
            let a = min(1, sparkleTime)
            let colors = [NSColor(hex: 0xFFD166), NSColor(hex: 0xFF8FA3), NSColor(hex: 0x8FD3FF)]
            for i in 0..<6 {
                let ang = CGFloat(i) / 6 * .pi * 2 + time * 1.5
                let r = 46 + (1.4 - sparkleTime) * 18
                let p = NSPoint(x: cx + cos(ang) * r, y: groundY + 34 + jumpY + sin(ang) * r * 0.7)
                drawStar(at: p, size: 5 + CGFloat(i % 2) * 2.5, color: colors[i % 3].withAlphaComponent(a))
            }
        }

        if heartTime > 0 {
            let progress = 1 - heartTime / 1.8
            for i in 0..<2 {
                let off = CGFloat(i) * 0.25
                let ph = max(0, progress - off)
                let x = cx + (i == 0 ? -14 : 16) + sin(ph * 8) * 3
                let y = top + 4 + ph * 40
                drawHeart(at: NSPoint(x: x, y: y), size: 9 - CGFloat(i) * 2,
                          color: NSColor(hex: 0xFF6B8B, alpha: max(0, 1 - ph)))
            }
        }
    }

    private func drawStar(at c: NSPoint, size: CGFloat, color: NSColor) {
        let p = NSBezierPath()
        for k in 0..<8 {
            let ang = CGFloat(k) * .pi / 4
            let r = k % 2 == 0 ? size : size * 0.32
            let pt = NSPoint(x: c.x + cos(ang) * r, y: c.y + sin(ang) * r)
            if k == 0 { p.move(to: pt) } else { p.line(to: pt) }
        }
        p.close()
        color.setFill(); p.fill()
    }

    private func drawHeart(at c: NSPoint, size s: CGFloat, color: NSColor) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x, y: c.y - s))
        p.curve(to: NSPoint(x: c.x, y: c.y + s * 0.45),
                controlPoint1: NSPoint(x: c.x - s * 1.4, y: c.y - s * 0.1),
                controlPoint2: NSPoint(x: c.x - s * 0.6, y: c.y + s * 1.1))
        p.curve(to: NSPoint(x: c.x, y: c.y - s),
                controlPoint1: NSPoint(x: c.x + s * 0.6, y: c.y + s * 1.1),
                controlPoint2: NSPoint(x: c.x + s * 1.4, y: c.y - s * 0.1))
        color.setFill(); p.fill()
    }

    // MARK: Bubble

    private func drawBubble(_ ctx: CGContext) {
        guard let b = bubble else { return }
        ctx.saveGState()
        ctx.setAlpha(bubbleAlpha)

        let accent: NSColor
        switch b.kind {
        case .mail: accent = NSColor(hex: 0xE2556B)
        case .calendar: accent = NSColor(hex: 0x3D84D6)
        case .info: accent = NSColor(hex: 0x8A6A55)
        }

        let pad: CGFloat = 12
        let maxContent: CGFloat = 236
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        para.lineSpacing = 1

        let title = NSAttributedString(string: b.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .bold), .foregroundColor: accent])
        let body = NSAttributedString(string: b.body, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor(hex: 0x3E3238), .paragraphStyle: para])
        let hint = b.hint.map {
            NSAttributedString(string: $0, attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor(hex: 0xA08C80)])
        }

        let titleSize = title.size()
        let bodyBox = body.boundingRect(with: NSSize(width: maxContent, height: 1000),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading])
        let contentW = min(maxContent, max(ceil(titleSize.width), ceil(bodyBox.width), ceil(hint?.size().width ?? 0), 110))
        let titleH = ceil(titleSize.height)
        let bodyH = b.body.isEmpty ? 0 : min(ceil(bodyBox.height), 66)
        let hintH = hint.map { ceil($0.size().height) + 3 } ?? 0
        let w = contentW + pad * 2
        let h = pad + titleH + (bodyH > 0 ? 3 + bodyH : 0) + hintH + pad - 2

        var x = bounds.midX - w / 2
        x = min(max(x, visibleRange.lowerBound + 6), visibleRange.upperBound - w - 6)
        let y: CGFloat = groundY + 96
        let rect = NSRect(x: x, y: y, width: w, height: h)

        // tail point toward Mochi's head
        let tx = min(max(bounds.midX, rect.minX + 22), rect.maxX - 22)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: tx - 9, y: y + 1))
        tail.line(to: NSPoint(x: tx - 2, y: y - 11))
        tail.line(to: NSPoint(x: tx + 9, y: y + 1))
        tail.close()

        let card = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 10, color: NSColor(white: 0, alpha: 0.28).cgColor)
        NSColor(hex: 0xFFFDF9).setFill()
        card.fill()
        tail.fill()
        ctx.restoreGState()

        NSColor(hex: 0xEAD7C8).setStroke()
        card.lineWidth = 1.2
        card.stroke()
        NSColor(hex: 0xFFFDF9).setFill()
        tail.fill()
        let edges = NSBezierPath()
        edges.move(to: NSPoint(x: tx - 9, y: y + 0.6))
        edges.line(to: NSPoint(x: tx - 2, y: y - 11))
        edges.line(to: NSPoint(x: tx + 9, y: y + 0.6))
        edges.lineWidth = 1.2
        edges.lineJoinStyle = .round
        NSColor(hex: 0xEAD7C8).setStroke()
        edges.stroke()

        // accent stripe
        accent.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX + 6, y: rect.minY + 10, width: 3, height: rect.height - 20),
                     xRadius: 1.5, yRadius: 1.5).fill()

        var cursorY = rect.maxY - pad + 1
        cursorY -= titleH
        title.draw(with: NSRect(x: rect.minX + pad, y: cursorY, width: contentW, height: titleH),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        if bodyH > 0 {
            cursorY -= 3 + bodyH
            body.draw(with: NSRect(x: rect.minX + pad, y: cursorY, width: contentW, height: bodyH),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        if let hint = hint {
            cursorY -= hintH
            hint.draw(with: NSRect(x: rect.minX + pad, y: cursorY, width: contentW, height: hintH),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }

        ctx.restoreGState()
        bubbleRect = rect.union(NSRect(x: tx - 10, y: y - 12, width: 20, height: 14))
    }
}
