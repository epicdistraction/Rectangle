/// DirectionalResizeCalculation.swift

import Cocoa

enum DirectionalResizePlacement: CaseIterable, Equatable {
    case topLeftCorner
    case topRightCorner
    case bottomLeftCorner
    case bottomRightCorner
    case leftSide
    case rightSide
    case topSide
    case bottomSide
    case floatingOrAmbiguous
}

enum DirectionalResizeDirection: Equatable {
    case up, down, left, right
}

enum DirectionalResizeOperation: Equatable {
    case expand, contract
}

struct DirectionalResizeIntent {
    let placement: DirectionalResizePlacement
    let direction: DirectionalResizeDirection
    let axis: CornerCycleExpansionAxis
    let operation: DirectionalResizeOperation
    let movedEdge: CooperativeCornerResize.MovedEdge
    let placementAction: WindowAction

    func usesFullSplitBoundary(cyclicCornerAxis: CornerCycleExpansionAxis) -> Bool {
        placementAction.isCooperativeCornerAction && axis != cyclicCornerAxis
    }

    static func resolve(placement: DirectionalResizePlacement,
                        direction: DirectionalResizeDirection) -> DirectionalResizeIntent? {
        let horizontalAnchor: HalfSplitSide?
        let verticalAnchor: HalfSplitSide?

        switch placement {
        case .topLeftCorner:
            horizontalAnchor = .leading
            verticalAnchor = .leading
        case .topRightCorner:
            horizontalAnchor = .trailing
            verticalAnchor = .leading
        case .bottomLeftCorner:
            horizontalAnchor = .leading
            verticalAnchor = .trailing
        case .bottomRightCorner:
            horizontalAnchor = .trailing
            verticalAnchor = .trailing
        case .leftSide:
            horizontalAnchor = .leading
            verticalAnchor = nil
        case .rightSide:
            horizontalAnchor = .trailing
            verticalAnchor = nil
        case .topSide:
            horizontalAnchor = nil
            verticalAnchor = .leading
        case .bottomSide:
            horizontalAnchor = nil
            verticalAnchor = .trailing
        case .floatingOrAmbiguous:
            return nil
        }

        let axis: CornerCycleExpansionAxis
        let operation: DirectionalResizeOperation
        let movedEdge: CooperativeCornerResize.MovedEdge

        switch direction {
        case .left, .right:
            guard let horizontalAnchor else { return nil }
            axis = .horizontal
            movedEdge = horizontalAnchor == .leading ? .right : .left
            operation = (direction == .right) == (horizontalAnchor == .leading) ? .expand : .contract
        case .up, .down:
            guard let verticalAnchor else { return nil }
            axis = .vertical
            movedEdge = verticalAnchor == .leading ? .bottom : .top
            operation = (direction == .down) == (verticalAnchor == .leading) ? .expand : .contract
        }

        guard let placementAction = placement.windowAction else { return nil }
        return DirectionalResizeIntent(placement: placement,
                                       direction: direction,
                                       axis: axis,
                                       operation: operation,
                                       movedEdge: movedEdge,
                                       placementAction: placementAction)
    }
}

extension DirectionalResizePlacement {
    var windowAction: WindowAction? {
        switch self {
        case .topLeftCorner: return .topLeft
        case .topRightCorner: return .topRight
        case .bottomLeftCorner: return .bottomLeft
        case .bottomRightCorner: return .bottomRight
        case .leftSide: return .leftHalf
        case .rightSide: return .rightHalf
        case .topSide: return .topHalf
        case .bottomSide: return .bottomHalf
        case .floatingOrAmbiguous: return nil
        }
    }
}

extension WindowAction {
    var directionalResizeDirection: DirectionalResizeDirection? {
        switch self {
        case .resizeUp: return .up
        case .resizeDown: return .down
        case .resizeLeft: return .left
        case .resizeRight: return .right
        default: return nil
        }
    }
}

struct DirectionalResizePlacementClassifier {
    static func classify(frame: CGRect,
                         screenFrame: CGRect,
                         gapSize: CGFloat,
                         tolerance: CGFloat? = nil) -> DirectionalResizePlacement {
        guard !frame.isNull,
              !screenFrame.isNull,
              screenFrame.width > 0,
              screenFrame.height > 0,
              screenFrame.intersects(frame)
        else {
            return .floatingOrAmbiguous
        }

        let resolvedTolerance = tolerance
            ?? CooperativeCornerResize.detectionTolerance(screenFrame: screenFrame, configuredGap: gapSize)
        let gap = max(0, gapSize)
        let touchesLeft = matches(frame.minX, outer: screenFrame.minX, inset: gap, tolerance: resolvedTolerance)
        let touchesRight = matches(frame.maxX, outer: screenFrame.maxX, inset: -gap, tolerance: resolvedTolerance)
        let touchesBottom = matches(frame.minY, outer: screenFrame.minY, inset: gap, tolerance: resolvedTolerance)
        let topInset = Defaults.skipGapTopEdge.enabled ? 0 : -gap
        let touchesTop = matches(frame.maxY, outer: screenFrame.maxY, inset: topInset, tolerance: resolvedTolerance)

        // A side spans the perpendicular dimension. Check it before corners so a
        // full-height left window is not mistaken for both left corners.
        if touchesTop && touchesBottom {
            if touchesLeft != touchesRight { return touchesLeft ? .leftSide : .rightSide }
            return .floatingOrAmbiguous
        }
        if touchesLeft && touchesRight {
            if touchesTop != touchesBottom { return touchesTop ? .topSide : .bottomSide }
            return .floatingOrAmbiguous
        }

        switch (touchesLeft, touchesRight, touchesTop, touchesBottom) {
        case (true, false, true, false): return .topLeftCorner
        case (false, true, true, false): return .topRightCorner
        case (true, false, false, true): return .bottomLeftCorner
        case (false, true, false, true): return .bottomRightCorner
        default:
            break
        }

        // For a slightly detached frame, infer only when one outer edge is both
        // nearby and decisively closer than its opposite. Centered/floating
        // frames therefore remain no-ops.
        let horizontalCapture = CooperativeCornerResize.captureTolerance(screenFrame: screenFrame, axis: .horizontal)
        let verticalCapture = CooperativeCornerResize.captureTolerance(screenFrame: screenFrame, axis: .vertical)
        let horizontalSide = confidentSide(leadingDistance: edgeDistance(frame.minX,
                                                                         outer: screenFrame.minX,
                                                                         inset: gap),
                                            trailingDistance: edgeDistance(frame.maxX,
                                                                           outer: screenFrame.maxX,
                                                                           inset: -gap),
                                            captureTolerance: horizontalCapture,
                                            decisivenessTolerance: resolvedTolerance)
        let verticalSide = confidentSide(leadingDistance: edgeDistance(frame.maxY,
                                                                       outer: screenFrame.maxY,
                                                                       inset: topInset),
                                          trailingDistance: edgeDistance(frame.minY,
                                                                         outer: screenFrame.minY,
                                                                         inset: gap),
                                          captureTolerance: verticalCapture,
                                          decisivenessTolerance: resolvedTolerance)

        switch (horizontalSide, verticalSide) {
        case (.leading?, .leading?): return .topLeftCorner
        case (.trailing?, .leading?): return .topRightCorner
        case (.leading?, .trailing?): return .bottomLeftCorner
        case (.trailing?, .trailing?): return .bottomRightCorner
        case (.leading?, nil): return .leftSide
        case (.trailing?, nil): return .rightSide
        case (nil, .leading?): return .topSide
        case (nil, .trailing?): return .bottomSide
        case (nil, nil): return .floatingOrAmbiguous
        }
    }

    private static func matches(_ value: CGFloat,
                                outer: CGFloat,
                                inset: CGFloat,
                                tolerance: CGFloat) -> Bool {
        min(abs(value - outer), abs(value - (outer + inset))) <= tolerance
    }

    private static func edgeDistance(_ value: CGFloat, outer: CGFloat, inset: CGFloat) -> CGFloat {
        min(abs(value - outer), abs(value - (outer + inset)))
    }

    private static func confidentSide(leadingDistance: CGFloat,
                                      trailingDistance: CGFloat,
                                      captureTolerance: CGFloat,
                                      decisivenessTolerance: CGFloat) -> HalfSplitSide? {
        let nearest = min(leadingDistance, trailingDistance)
        guard nearest <= captureTolerance,
              abs(leadingDistance - trailingDistance) >= decisivenessTolerance
        else {
            return nil
        }
        return leadingDistance < trailingDistance ? .leading : .trailing
    }
}

final class DirectionalResizeCalculation: WindowCalculation {
    struct Resolution {
        let rect: CGRect
        let intent: DirectionalResizeIntent?
    }

    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let screen = params.usableScreens.currentScreen
        let screenFrame = screen.adjustedVisibleFrame(params.ignoreTodo)
        let resolution = resolve(action: params.action,
                                 currentFrame: params.window.rect,
                                 screenFrame: screenFrame,
                                 gapSize: max(0, CGFloat(Defaults.gapSize.value)))

        guard let intent = resolution.intent else {
            return WindowCalculationResult(rect: resolution.rect,
                                           screen: screen,
                                           resultingAction: params.action,
                                           isNoOp: true)
        }
        return WindowCalculationResult(rect: resolution.rect,
                                       screen: screen,
                                       resultingAction: intent.placementAction,
                                       directionalResizeIntent: intent)
    }

    func resolve(action: WindowAction,
                 currentFrame: CGRect,
                 screenFrame: CGRect,
                 gapSize: CGFloat = 0) -> Resolution {
        guard let direction = action.directionalResizeDirection else {
            return Resolution(rect: currentFrame, intent: nil)
        }
        let placement = DirectionalResizePlacementClassifier.classify(frame: currentFrame,
                                                                      screenFrame: screenFrame,
                                                                      gapSize: gapSize)
        guard let intent = DirectionalResizeIntent.resolve(placement: placement, direction: direction),
              let targetFraction = nextFraction(currentFrame: currentFrame,
                                                screenFrame: screenFrame,
                                                gapSize: gapSize,
                                                intent: intent)
        else {
            return Resolution(rect: currentFrame, intent: nil)
        }
        return Resolution(rect: rawTargetFrame(currentFrame: currentFrame,
                                               screenFrame: screenFrame,
                                               gapSize: gapSize,
                                               targetFraction: targetFraction,
                                               intent: intent),
                          intent: intent)
    }

    private func nextFraction(currentFrame: CGRect,
                              screenFrame: CGRect,
                              gapSize: CGFloat,
                              intent: DirectionalResizeIntent) -> Float? {
        let currentFraction = focusedFraction(frame: currentFrame,
                                              screenFrame: screenFrame,
                                              gapSize: gapSize,
                                              placement: intent.placement,
                                              axis: intent.axis)
        let fractions = selectedCycleSizes().map(\.fraction).sorted()
        let epsilon = max(CycleSize.matchingTolerance,
                          Float(1.0 / max(1, intent.axis == .horizontal ? screenFrame.width : screenFrame.height)))

        switch intent.operation {
        case .expand:
            return fractions.first { $0 > currentFraction + epsilon }
        case .contract:
            return fractions.last { $0 < currentFraction - epsilon }
        }
    }

    private func selectedCycleSizes() -> [CycleSize] {
        let positions = Defaults.cycleSizesIsChanged.enabled
            ? Defaults.selectedCycleSizes.value
            : CycleSize.defaultSizes
        return CycleSize.allCases.filter { positions.contains($0) }
    }

    private func rawTargetFrame(currentFrame: CGRect,
                                screenFrame: CGRect,
                                gapSize: CGFloat,
                                targetFraction: Float,
                                intent: DirectionalResizeIntent) -> CGRect {
        let horizontalSide = intent.placement.horizontalSide
        let verticalSide = intent.placement.verticalSide

        if let horizontalSide, verticalSide == nil {
            return HalfSplitFrameCalculation.horizontalRect(in: screenFrame,
                                                            side: horizontalSide,
                                                            fraction: targetFraction)
        }
        if let verticalSide, horizontalSide == nil {
            return HalfSplitFrameCalculation.verticalRect(in: screenFrame,
                                                          side: verticalSide,
                                                          fraction: targetFraction)
        }

        guard let horizontalSide, let verticalSide else { return currentFrame }
        let horizontalFraction = intent.axis == .horizontal
            ? targetFraction
            : focusedFraction(frame: currentFrame,
                              screenFrame: screenFrame,
                              gapSize: gapSize,
                              placement: intent.placement,
                              axis: .horizontal)
        let verticalFraction = intent.axis == .vertical
            ? targetFraction
            : focusedFraction(frame: currentFrame,
                              screenFrame: screenFrame,
                              gapSize: gapSize,
                              placement: intent.placement,
                              axis: .vertical)
        return HalfSplitFrameCalculation.cornerRect(in: screenFrame,
                                                    horizontalSide: horizontalSide,
                                                    verticalSide: verticalSide,
                                                    horizontalFraction: horizontalFraction,
                                                    verticalFraction: verticalFraction)
    }

    private func focusedFraction(frame: CGRect,
                                 screenFrame: CGRect,
                                 gapSize: CGFloat,
                                 placement: DirectionalResizePlacement,
                                 axis: CornerCycleExpansionAxis) -> Float {
        let halfGap = max(0, gapSize) / 2.0
        let fraction: CGFloat
        switch axis {
        case .horizontal:
            if placement.horizontalSide == .leading {
                fraction = (frame.maxX + halfGap - screenFrame.minX) / screenFrame.width
            } else {
                fraction = (screenFrame.maxX - (frame.minX - halfGap)) / screenFrame.width
            }
        case .vertical:
            if placement.verticalSide == .leading {
                fraction = (screenFrame.maxY - (frame.minY - halfGap)) / screenFrame.height
            } else {
                fraction = (frame.maxY + halfGap - screenFrame.minY) / screenFrame.height
            }
        }
        return Float(min(1, max(0, fraction)))
    }
}

private extension DirectionalResizePlacement {
    var horizontalSide: HalfSplitSide? {
        switch self {
        case .topLeftCorner, .bottomLeftCorner, .leftSide: return .leading
        case .topRightCorner, .bottomRightCorner, .rightSide: return .trailing
        case .topSide, .bottomSide, .floatingOrAmbiguous: return nil
        }
    }

    var verticalSide: HalfSplitSide? {
        switch self {
        case .topLeftCorner, .topRightCorner, .topSide: return .leading
        case .bottomLeftCorner, .bottomRightCorner, .bottomSide: return .trailing
        case .leftSide, .rightSide, .floatingOrAmbiguous: return nil
        }
    }
}
