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

enum DirectionalResizeTargetMode: Equatable {
    case step, max
}

enum DirectionalResizeEndpointAction: Equatable {
    case stepResize
    case promoteCornerToSide
    case placeSideIntoCorner
    case noop
}

struct DirectionalResizeIntent {
    let placement: DirectionalResizePlacement
    let direction: DirectionalResizeDirection
    let axis: CornerCycleExpansionAxis
    let operation: DirectionalResizeOperation
    let movedEdge: CooperativeCornerResize.MovedEdge
    let placementAction: WindowAction
    let targetMode: DirectionalResizeTargetMode
    let endpointAction: DirectionalResizeEndpointAction

    func usesFullSplitBoundary(cyclicCornerAxis: CornerCycleExpansionAxis) -> Bool {
        placementAction.isCooperativeCornerAction && axis != cyclicCornerAxis
    }

    func acceptsCooperativeFocusedFrame(_ focusedFrame: CGRect,
                                        requestedFrame: CGRect,
                                        tolerance: CGFloat = 4) -> Bool {
        guard endpointAction == .promoteCornerToSide else { return true }
        return abs(focusedFrame.minX - requestedFrame.minX) <= tolerance
            && abs(focusedFrame.minY - requestedFrame.minY) <= tolerance
            && abs(focusedFrame.width - requestedFrame.width) <= tolerance
            && abs(focusedFrame.height - requestedFrame.height) <= tolerance
    }

    static func resolve(placement: DirectionalResizePlacement,
                        direction: DirectionalResizeDirection,
                        targetMode: DirectionalResizeTargetMode = .step) -> DirectionalResizeIntent? {
        if let cornerPlacement = placement.cornerPlacement(for: direction),
           let placementAction = cornerPlacement.windowAction,
           let horizontalSide = cornerPlacement.horizontalSide,
           let verticalSide = cornerPlacement.verticalSide {
            let axis: CornerCycleExpansionAxis = direction == .left || direction == .right ? .horizontal : .vertical
            let movedEdge: CooperativeCornerResize.MovedEdge = axis == .horizontal
                ? (horizontalSide == .leading ? .right : .left)
                : (verticalSide == .leading ? .bottom : .top)
            return DirectionalResizeIntent(placement: placement,
                                           direction: direction,
                                           axis: axis,
                                           operation: .contract,
                                           movedEdge: movedEdge,
                                           placementAction: placementAction,
                                           targetMode: targetMode,
                                           endpointAction: .placeSideIntoCorner)
        }

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
                                       placementAction: placementAction,
                                       targetMode: targetMode,
                                       endpointAction: .stepResize)
    }

    func promotingCornerToSide() -> DirectionalResizeIntent? {
        guard endpointAction == .stepResize,
              operation == .expand,
              let sidePlacement = placement.promotedSide(for: axis),
              let placementAction = sidePlacement.windowAction
        else {
            return nil
        }
        return DirectionalResizeIntent(placement: placement,
                                       direction: direction,
                                       axis: axis,
                                       operation: operation,
                                       movedEdge: movedEdge,
                                       placementAction: placementAction,
                                       targetMode: targetMode,
                                       endpointAction: .promoteCornerToSide)
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
        case .maxResizeUp: return .up
        case .maxResizeDown: return .down
        case .maxResizeLeft: return .left
        case .maxResizeRight: return .right
        default: return nil
        }
    }

    var directionalResizeTargetMode: DirectionalResizeTargetMode? {
        switch self {
        case .resizeUp, .resizeDown, .resizeLeft, .resizeRight:
            return .step
        case .maxResizeUp, .maxResizeDown, .maxResizeLeft, .maxResizeRight:
            return .max
        default:
            return nil
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

        var endpointAction: DirectionalResizeEndpointAction {
            intent?.endpointAction ?? .noop
        }
    }

    override func calculate(_ params: WindowCalculationParameters) -> WindowCalculationResult? {
        let screen = params.usableScreens.currentScreen
        let screenFrame = screen.adjustedVisibleFrame(params.ignoreTodo)
        let resolution = resolve(action: params.action,
                                 windowId: params.window.id,
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
                 windowId: CGWindowID? = nil,
                 currentFrame: CGRect,
                 screenFrame: CGRect,
                 gapSize: CGFloat = 0) -> Resolution {
        guard let direction = action.directionalResizeDirection,
              let targetMode = action.directionalResizeTargetMode else {
            return Resolution(rect: currentFrame, intent: nil)
        }
        let placement = DirectionalResizePlacementClassifier.classify(frame: currentFrame,
                                                                      screenFrame: screenFrame,
                                                                      gapSize: gapSize)
        let reachedConstrainedEndpoint = windowId.map {
            DirectionalResizeEndpointState.shared.consumeConstrainedEndpointIfMatching(windowId: $0,
                                                                                       direction: direction,
                                                                                       placement: placement,
                                                                                       currentFrame: currentFrame,
                                                                                       screenFrame: screenFrame)
        } ?? false
        guard let intent = DirectionalResizeIntent.resolve(placement: placement,
                                                           direction: direction,
                                                           targetMode: targetMode) else {
            return Resolution(rect: currentFrame, intent: nil)
        }

        if intent.endpointAction == .placeSideIntoCorner {
            guard let targetFraction = selectedCycleSizes().map(\.fraction).max() else {
                return Resolution(rect: currentFrame, intent: nil)
            }
            return Resolution(rect: sideToCornerTargetFrame(currentFrame: currentFrame,
                                                            screenFrame: screenFrame,
                                                            gapSize: gapSize,
                                                            targetFraction: targetFraction,
                                                            intent: intent),
                              intent: intent)
        }

        guard let targetFraction = nextFraction(currentFrame: currentFrame,
                                                screenFrame: screenFrame,
                                                gapSize: gapSize,
                                                intent: intent) else {
            guard intent.operation == .expand,
                  intent.placement.isCorner,
                  (reachedConstrainedEndpoint || isAtMaximumFraction(currentFrame: currentFrame,
                                                                     screenFrame: screenFrame,
                                                                     gapSize: gapSize,
                                                                     intent: intent)),
                  let promotionIntent = intent.promotingCornerToSide()
            else {
                return Resolution(rect: currentFrame, intent: nil)
            }
            return Resolution(rect: cornerToSideTargetFrame(currentFrame: currentFrame,
                                                            screenFrame: screenFrame,
                                                            gapSize: gapSize,
                                                            intent: promotionIntent),
                              intent: promotionIntent)
        }

        if reachedConstrainedEndpoint,
           intent.operation == .expand,
           let promotionIntent = intent.promotingCornerToSide() {
            return Resolution(rect: cornerToSideTargetFrame(currentFrame: currentFrame,
                                                            screenFrame: screenFrame,
                                                            gapSize: gapSize,
                                                            intent: promotionIntent),
                              intent: promotionIntent)
        }
        return Resolution(rect: rawTargetFrame(currentFrame: currentFrame,
                                               screenFrame: screenFrame,
                                               gapSize: gapSize,
                                               targetFraction: targetFraction,
                                               intent: intent),
                          intent: intent)
    }

    private func isAtMaximumFraction(currentFrame: CGRect,
                                     screenFrame: CGRect,
                                     gapSize: CGFloat,
                                     intent: DirectionalResizeIntent) -> Bool {
        guard let maximumFraction = selectedCycleSizes().map(\.fraction).max() else { return false }
        let currentFraction = focusedFraction(frame: currentFrame,
                                              screenFrame: screenFrame,
                                              gapSize: gapSize,
                                              placement: intent.placement,
                                              axis: intent.axis)
        let epsilon = max(CycleSize.matchingTolerance,
                          Float(1.0 / max(1, intent.axis == .horizontal ? screenFrame.width : screenFrame.height)))
        return currentFraction >= maximumFraction - epsilon
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

        switch (intent.targetMode, intent.operation) {
        case (.step, .expand):
            return fractions.first { $0 > currentFraction + epsilon }
        case (.step, .contract):
            return fractions.last { $0 < currentFraction - epsilon }
        case (.max, .expand):
            return fractions.last { $0 > currentFraction + epsilon }
        case (.max, .contract):
            return fractions.first { $0 < currentFraction - epsilon }
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

    private func cornerToSideTargetFrame(currentFrame: CGRect,
                                         screenFrame: CGRect,
                                         gapSize: CGFloat,
                                         intent: DirectionalResizeIntent) -> CGRect {
        switch intent.axis {
        case .vertical:
            guard let horizontalSide = intent.placement.horizontalSide else { return currentFrame }
            let horizontalFraction = focusedFraction(frame: currentFrame,
                                                     screenFrame: screenFrame,
                                                     gapSize: gapSize,
                                                     placement: intent.placement,
                                                     axis: .horizontal)
            return HalfSplitFrameCalculation.horizontalRect(in: screenFrame,
                                                            side: horizontalSide,
                                                            fraction: horizontalFraction)
        case .horizontal:
            guard let verticalSide = intent.placement.verticalSide else { return currentFrame }
            let verticalFraction = focusedFraction(frame: currentFrame,
                                                   screenFrame: screenFrame,
                                                   gapSize: gapSize,
                                                   placement: intent.placement,
                                                   axis: .vertical)
            return HalfSplitFrameCalculation.verticalRect(in: screenFrame,
                                                          side: verticalSide,
                                                          fraction: verticalFraction)
        }
    }

    private func sideToCornerTargetFrame(currentFrame: CGRect,
                                         screenFrame: CGRect,
                                         gapSize: CGFloat,
                                         targetFraction: Float,
                                         intent: DirectionalResizeIntent) -> CGRect {
        guard let targetPlacement = DirectionalResizePlacement.from(windowAction: intent.placementAction),
              let horizontalSide = targetPlacement.horizontalSide,
              let verticalSide = targetPlacement.verticalSide
        else {
            return currentFrame
        }
        let horizontalFraction: Float
        let verticalFraction: Float
        if intent.axis == .vertical {
            horizontalFraction = focusedFraction(frame: currentFrame,
                                                 screenFrame: screenFrame,
                                                 gapSize: gapSize,
                                                 placement: intent.placement,
                                                 axis: .horizontal)
            verticalFraction = targetFraction
        } else {
            horizontalFraction = targetFraction
            verticalFraction = focusedFraction(frame: currentFrame,
                                               screenFrame: screenFrame,
                                               gapSize: gapSize,
                                               placement: intent.placement,
                                               axis: .vertical)
        }
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

final class DirectionalResizeEndpointState {
    static let shared = DirectionalResizeEndpointState()

    private struct Entry {
        let direction: DirectionalResizeDirection
        let placement: DirectionalResizePlacement
        let achievedFrame: CGRect
        let screenFrame: CGRect
    }

    private var entries = [CGWindowID: Entry]()

    func consumeConstrainedEndpointIfMatching(windowId: CGWindowID,
                                              direction: DirectionalResizeDirection,
                                              placement: DirectionalResizePlacement,
                                              currentFrame: CGRect,
                                              screenFrame: CGRect) -> Bool {
        guard let entry = entries.removeValue(forKey: windowId) else { return false }
        return entry.direction == direction
            && entry.placement == placement
            && framesMatch(entry.achievedFrame, currentFrame)
            && framesMatch(entry.screenFrame, screenFrame)
    }

    func recordAttempt(windowId: CGWindowID,
                       intent: DirectionalResizeIntent,
                       previousFrame: CGRect,
                       requestedFrame: CGRect,
                       achievedFrame: CGRect,
                       screenFrame: CGRect) {
        entries.removeValue(forKey: windowId)
        guard intent.endpointAction == .stepResize,
              intent.operation == .expand,
              intent.placement.isCorner
        else {
            return
        }

        let oldSize = dimension(of: previousFrame, axis: intent.axis)
        let requestedSize = dimension(of: requestedFrame, axis: intent.axis)
        let achievedSize = dimension(of: achievedFrame, axis: intent.axis)
        let tolerance = max(1.0, dimension(of: screenFrame, axis: intent.axis) * 0.001)
        guard achievedSize >= oldSize - tolerance,
              requestedSize > achievedSize + tolerance
        else {
            return
        }
        entries[windowId] = Entry(direction: intent.direction,
                                  placement: intent.placement,
                                  achievedFrame: achievedFrame,
                                  screenFrame: screenFrame)
    }

    func resetAll() {
        entries.removeAll()
    }

    private func dimension(of frame: CGRect, axis: CornerCycleExpansionAxis) -> CGFloat {
        axis == .horizontal ? frame.width : frame.height
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 2
            && abs(lhs.minY - rhs.minY) <= 2
            && abs(lhs.width - rhs.width) <= 2
            && abs(lhs.height - rhs.height) <= 2
    }
}

final class DirectionalResizeDisplacementState {
    static let shared = DirectionalResizeDisplacementState()

    struct Entry {
        struct ReconciledFrames {
            let focusedFrame: CGRect
            let fillFrame: CGRect
        }

        let direction: DirectionalResizeDirection
        let originPlacement: DirectionalResizePlacement
        let displacedWindowIds: [CGWindowID]
        let sideFrame: CGRect
        let screenFrame: CGRect

        func complementaryRawFrame(destinationCornerFrame: CGRect) -> CGRect? {
            var frame = destinationCornerFrame
            switch direction {
            case .down:
                frame.origin.y = destinationCornerFrame.maxY
                frame.size.height = screenFrame.maxY - destinationCornerFrame.maxY
            case .up:
                frame.origin.y = screenFrame.minY
                frame.size.height = destinationCornerFrame.minY - screenFrame.minY
            case .right:
                frame.origin.x = screenFrame.minX
                frame.size.width = destinationCornerFrame.minX - screenFrame.minX
            case .left:
                frame.origin.x = destinationCornerFrame.maxX
                frame.size.width = screenFrame.maxX - destinationCornerFrame.maxX
            }
            guard frame.width > 0, frame.height > 0 else { return nil }
            return frame
        }

        func reconciledFrames(requestedFocusedFrame: CGRect,
                              requestedFillFrame: CGRect,
                              realizedFillFrames: [CGRect]) -> ReconciledFrames {
            let requestedFillSize = axisSize(requestedFillFrame)
            let realizedFillSize = realizedFillFrames.map(axisSize).max() ?? requestedFillSize
            let fillSize = max(requestedFillSize, realizedFillSize)
            var fillFrame = requestedFillFrame
            var focusedFrame = requestedFocusedFrame

            switch direction {
            case .up:
                let gap = max(0, requestedFocusedFrame.minY - requestedFillFrame.maxY)
                fillFrame.size.height = fillSize
                focusedFrame.origin.y = fillFrame.maxY + gap
                focusedFrame.size.height = max(0, requestedFocusedFrame.maxY - focusedFrame.minY)
            case .down:
                let gap = max(0, requestedFillFrame.minY - requestedFocusedFrame.maxY)
                fillFrame.origin.y = requestedFillFrame.maxY - fillSize
                fillFrame.size.height = fillSize
                focusedFrame.size.height = max(0, fillFrame.minY - gap - requestedFocusedFrame.minY)
            case .right:
                let gap = max(0, requestedFocusedFrame.minX - requestedFillFrame.maxX)
                fillFrame.size.width = fillSize
                focusedFrame.origin.x = fillFrame.maxX + gap
                focusedFrame.size.width = max(0, requestedFocusedFrame.maxX - focusedFrame.minX)
            case .left:
                let gap = max(0, requestedFillFrame.minX - requestedFocusedFrame.maxX)
                fillFrame.origin.x = requestedFillFrame.maxX - fillSize
                fillFrame.size.width = fillSize
                focusedFrame.size.width = max(0, fillFrame.minX - gap - requestedFocusedFrame.minX)
            }
            return ReconciledFrames(focusedFrame: focusedFrame, fillFrame: fillFrame)
        }

        private func axisSize(_ frame: CGRect) -> CGFloat {
            direction == .left || direction == .right ? frame.width : frame.height
        }
    }

    private var entries = [CGWindowID: Entry]()

    func recordFallbackPromotion(windowId: CGWindowID,
                                 intent: DirectionalResizeIntent,
                                 displacedWindowIds: [CGWindowID],
                                 sideFrame: CGRect,
                                 screenFrame: CGRect) {
        entries.removeValue(forKey: windowId)
        let uniqueWindowIds = Array(Set(displacedWindowIds)).sorted()
        guard intent.endpointAction == .promoteCornerToSide,
              intent.placement.isCorner,
              !uniqueWindowIds.isEmpty
        else {
            return
        }
        entries[windowId] = Entry(direction: intent.direction,
                                  originPlacement: intent.placement,
                                  displacedWindowIds: uniqueWindowIds,
                                  sideFrame: sideFrame,
                                  screenFrame: screenFrame)
    }

    func consumeIfMatching(windowId: CGWindowID,
                           intent: DirectionalResizeIntent?,
                           currentFrame: CGRect,
                           screenFrame: CGRect) -> Entry? {
        guard let entry = entries.removeValue(forKey: windowId),
              let intent,
              intent.endpointAction == .placeSideIntoCorner,
              intent.direction == entry.direction,
              framesMatch(entry.sideFrame,
                          currentFrame,
                          tolerance: CooperativeCornerResize.detectionTolerance(
                            screenFrame: screenFrame,
                            configuredGap: max(0, CGFloat(Defaults.gapSize.value))
                          )),
              framesMatch(entry.screenFrame, screenFrame, tolerance: 2)
        else {
            return nil
        }
        return entry
    }

    func resetAll() {
        entries.removeAll()
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}

private extension DirectionalResizePlacement {
    var isCorner: Bool {
        switch self {
        case .topLeftCorner, .topRightCorner, .bottomLeftCorner, .bottomRightCorner:
            return true
        default:
            return false
        }
    }

    func cornerPlacement(for direction: DirectionalResizeDirection) -> DirectionalResizePlacement? {
        switch (self, direction) {
        case (.rightSide, .up): return .topRightCorner
        case (.rightSide, .down): return .bottomRightCorner
        case (.leftSide, .up): return .topLeftCorner
        case (.leftSide, .down): return .bottomLeftCorner
        case (.topSide, .left): return .topLeftCorner
        case (.topSide, .right): return .topRightCorner
        case (.bottomSide, .left): return .bottomLeftCorner
        case (.bottomSide, .right): return .bottomRightCorner
        default: return nil
        }
    }

    func promotedSide(for axis: CornerCycleExpansionAxis) -> DirectionalResizePlacement? {
        switch (self, axis) {
        case (.topLeftCorner, .vertical), (.bottomLeftCorner, .vertical): return .leftSide
        case (.topRightCorner, .vertical), (.bottomRightCorner, .vertical): return .rightSide
        case (.topLeftCorner, .horizontal), (.topRightCorner, .horizontal): return .topSide
        case (.bottomLeftCorner, .horizontal), (.bottomRightCorner, .horizontal): return .bottomSide
        default: return nil
        }
    }

    static func from(windowAction: WindowAction) -> DirectionalResizePlacement? {
        switch windowAction {
        case .topLeft: return .topLeftCorner
        case .topRight: return .topRightCorner
        case .bottomLeft: return .bottomLeftCorner
        case .bottomRight: return .bottomRightCorner
        case .leftHalf: return .leftSide
        case .rightHalf: return .rightSide
        case .topHalf: return .topSide
        case .bottomHalf: return .bottomSide
        default: return nil
        }
    }

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
