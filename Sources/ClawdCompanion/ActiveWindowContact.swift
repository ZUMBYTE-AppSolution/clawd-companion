import CoreGraphics

/// Contact geometry for a deliberate climb of the front window. The outer
/// panel includes transparent pixels, so use the sprite's grip and foot rows.
struct ActiveWindowContact {
    enum Side { case left, right }
    let window: SceneryWindow
    let size: CGSize

    func side(near x: CGFloat) -> Side {
        if !window.leftClear { return .right }
        if !window.rightClear { return .left }
        if window.leftRoofClear != window.rightRoofClear { return window.leftRoofClear ? .left : .right }
        return abs(x - window.frame.minX) < abs(x - window.frame.maxX) ? .left : .right
    }

    func clear(_ side: Side) -> Bool { side == .left ? window.leftClear : window.rightClear }
    func canStand(_ side: Side) -> Bool {
        (side == .left ? window.leftRoofClear : window.rightRoofClear)
            && WindowLedge.standY(window: window.frame, screen: window.screen, pet: size) != nil
    }

    func looksLeft(on side: Side) -> Bool { side == .left ? window.leftInside : !window.rightInside }

    func wall(_ side: Side, upper: Bool) -> CGPoint {
        let edge = side == .left ? window.frame.minX : window.frame.maxX
        let wrist: CGFloat = looksLeft(on: side) ? 5 : 51
        let x = edge - size.width * wrist / 56
        let top = WindowLedge.gripY(window: window.frame, screen: window.screen, pet: size)
        let bottom = min(top, max(window.screen.minY, window.frame.minY + 6))
        return CGPoint(x: x, y: upper ? top : bottom)
    }

    func rest(_ side: Side, pose: MascotPose) -> CGPoint {
        guard canStand(side), let stand = WindowLedge.standY(window: window.frame, screen: window.screen, pet: size)
        else {
            var position = wall(side, upper: true)
            // This prop has a clipboard clip in row four. The grip's six
            // transparent rows belong to the climbing drawing alone.
            if pose == .planning || pose == .drawing {
                position.y = min(position.y, window.screen.maxY - WindowLedge.offset(forRow: 4, pet: size))
            }
            return position
        }
        // Settle just inside the clear portion of the actual ledge.
        let depth = min(size.width * 0.66, window.frame.width / 2)
        let center = side == .left ? window.frame.minX + depth : window.frame.maxX - depth
        let x = max(window.screen.minX, min(window.screen.maxX - size.width, center - size.width / 2))
        let y: CGFloat
        switch pose {
        case .perched, .perchThinking:
            y = WindowLedge.seatY(window: window.frame, screen: window.screen, pet: size) ?? stand
        case .typing:
            y = stand + WindowLedge.offset(forRow: 43, pet: size) - WindowLedge.offset(forRow: 42, pet: size)
        case .planning, .drawing, .executing:
            y = stand + WindowLedge.offset(forRow: 43, pet: size) - WindowLedge.offset(forRow: 44, pet: size)
        default: y = stand
        }
        return CGPoint(x: x, y: min(window.screen.maxY - size.height, y))
    }
}
