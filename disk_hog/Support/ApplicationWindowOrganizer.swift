import AppKit

enum ManagedApplicationWindowRole {
    case source
    case scan
    case inspector
}

struct ManagedWindowPlacementPlan: Equatable {
    let targetFrame: NSRect
    let movedObstacleIndex: Int?
    let movedObstacleFrame: NSRect?
}

@MainActor
final class ApplicationWindowPlacementService {
    static let shared: ApplicationWindowPlacementService = ApplicationWindowPlacementService()

    static let windowGap: CGFloat = 12
    static let screenInset: CGFloat = 16

    private var registeredWindows: [ObjectIdentifier: RegisteredApplicationWindow] = [:]

    private init() {}

    func register(_ window: NSWindow, role: ManagedApplicationWindowRole) {
        registeredWindows[ObjectIdentifier(window)] = RegisteredApplicationWindow(
            window: window,
            role: role
        )
    }

    func unregister(_ window: NSWindow) {
        registeredWindows[ObjectIdentifier(window)] = nil
    }

    func placeNewWindow(_ targetWindow: NSWindow) {
        removeReleasedWindows()
        guard let screen: NSScreen = targetWindow.screen ?? NSScreen.main else {
            return
        }

        let obstacles: [NSWindow] = registeredWindows.values.compactMap(\.window).filter {
            $0 !== targetWindow
                && $0.isVisible
                && ($0.screen === screen || $0.screen == nil)
        }
        let plan: ManagedWindowPlacementPlan = Self.placementPlan(
            targetFrame: targetWindow.frame,
            obstacleFrames: obstacles.map(\.frame),
            visibleFrame: screen.visibleFrame
        )
        if let movedIndex: Int = plan.movedObstacleIndex,
           obstacles.indices.contains(movedIndex),
           let movedFrame: NSRect = plan.movedObstacleFrame {
            obstacles[movedIndex].setFrame(movedFrame, display: true, animate: false)
        }
        targetWindow.setFrame(plan.targetFrame, display: true, animate: false)
    }

    static func placementPlan(
        targetFrame: NSRect,
        obstacleFrames: [NSRect],
        visibleFrame: NSRect
    ) -> ManagedWindowPlacementPlan {
        let usableFrame: NSRect = visibleFrame.insetBy(dx: screenInset, dy: screenInset)
        let fittedTarget: NSRect = fitted(targetFrame, within: usableFrame)
        let targetCandidates: [NSRect] = candidateFrames(
            for: fittedTarget,
            obstacles: obstacleFrames,
            usableFrame: usableFrame
        )

        if let clearFrame: NSRect = targetCandidates
            .filter({ overlapArea(of: $0, with: obstacleFrames) == 0 })
            .min(by: {
                movementDistance(from: fittedTarget, to: $0)
                    < movementDistance(from: fittedTarget, to: $1)
            }) {
            return ManagedWindowPlacementPlan(
                targetFrame: clearFrame,
                movedObstacleIndex: nil,
                movedObstacleFrame: nil
            )
        }

        var bestRearrangement: (
            targetFrame: NSRect,
            obstacleIndex: Int,
            obstacleFrame: NSRect,
            movement: CGFloat
        )?
        for (index, obstacleFrame) in obstacleFrames.enumerated() {
            let otherObstacles: [NSRect] = obstacleFrames.enumerated().compactMap {
                $0.offset == index ? nil : $0.element
            }
            for pair in pairedFrames(
                target: fittedTarget,
                obstacle: obstacleFrame,
                usableFrame: usableFrame
            ) {
                guard overlapArea(of: pair.target, with: otherObstacles) == 0,
                      overlapArea(of: pair.obstacle, with: otherObstacles) == 0 else {
                    continue
                }
                let movement: CGFloat = movementDistance(from: fittedTarget, to: pair.target)
                    + movementDistance(from: obstacleFrame, to: pair.obstacle)
                if bestRearrangement == nil || movement < bestRearrangement!.movement {
                    bestRearrangement = (pair.target, index, pair.obstacle, movement)
                }
            }
        }
        if let bestRearrangement {
            return ManagedWindowPlacementPlan(
                targetFrame: bestRearrangement.targetFrame,
                movedObstacleIndex: bestRearrangement.obstacleIndex,
                movedObstacleFrame: bestRearrangement.obstacleFrame
            )
        }

        let leastOverlappingFrame: NSRect = targetCandidates.min {
            let leftOverlap: CGFloat = overlapArea(of: $0, with: obstacleFrames)
            let rightOverlap: CGFloat = overlapArea(of: $1, with: obstacleFrames)
            if leftOverlap != rightOverlap {
                return leftOverlap < rightOverlap
            }
            return movementDistance(from: fittedTarget, to: $0)
                < movementDistance(from: fittedTarget, to: $1)
        } ?? fittedTarget
        return ManagedWindowPlacementPlan(
            targetFrame: leastOverlappingFrame,
            movedObstacleIndex: nil,
            movedObstacleFrame: nil
        )
    }

    private func removeReleasedWindows() {
        registeredWindows = registeredWindows.filter { $0.value.window != nil }
    }

    private static func candidateFrames(
        for target: NSRect,
        obstacles: [NSRect],
        usableFrame: NSRect
    ) -> [NSRect] {
        var xPositions: Set<CGFloat> = [
            target.minX,
            usableFrame.minX,
            usableFrame.maxX - target.width
        ]
        var yPositions: Set<CGFloat> = [
            target.minY,
            usableFrame.minY,
            usableFrame.maxY - target.height
        ]
        for obstacle: NSRect in obstacles {
            xPositions.insert(obstacle.minX - windowGap - target.width)
            xPositions.insert(obstacle.maxX + windowGap)
            yPositions.insert(obstacle.minY - windowGap - target.height)
            yPositions.insert(obstacle.maxY + windowGap)
        }

        var candidates: [NSRect] = [target]
        for xPosition: CGFloat in xPositions {
            for yPosition: CGFloat in yPositions {
                let candidate: NSRect = fitted(
                    NSRect(
                        x: xPosition,
                        y: yPosition,
                        width: target.width,
                        height: target.height
                    ),
                    within: usableFrame
                )
                if !candidates.contains(candidate) {
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }

    private static func pairedFrames(
        target: NSRect,
        obstacle: NSRect,
        usableFrame: NSRect
    ) -> [(target: NSRect, obstacle: NSRect)] {
        var results: [(target: NSRect, obstacle: NSRect)] = []
        let horizontalWidth: CGFloat = target.width + windowGap + obstacle.width
        if horizontalWidth <= usableFrame.width {
            let top: CGFloat = min(
                max(max(target.maxY, obstacle.maxY), usableFrame.minY + max(target.height, obstacle.height)),
                usableFrame.maxY
            )
            let groupX: CGFloat = min(
                max(min(target.minX, obstacle.minX), usableFrame.minX),
                usableFrame.maxX - horizontalWidth
            )
            results.append((
                target: NSRect(
                    x: groupX + obstacle.width + windowGap,
                    y: top - target.height,
                    width: target.width,
                    height: target.height
                ),
                obstacle: NSRect(
                    x: groupX,
                    y: top - obstacle.height,
                    width: obstacle.width,
                    height: obstacle.height
                )
            ))
            results.append((
                target: NSRect(
                    x: groupX,
                    y: top - target.height,
                    width: target.width,
                    height: target.height
                ),
                obstacle: NSRect(
                    x: groupX + target.width + windowGap,
                    y: top - obstacle.height,
                    width: obstacle.width,
                    height: obstacle.height
                )
            ))
        }

        let verticalHeight: CGFloat = target.height + windowGap + obstacle.height
        if verticalHeight <= usableFrame.height {
            let left: CGFloat = min(
                max(min(target.minX, obstacle.minX), usableFrame.minX),
                usableFrame.maxX - max(target.width, obstacle.width)
            )
            let groupY: CGFloat = min(
                max(min(target.minY, obstacle.minY), usableFrame.minY),
                usableFrame.maxY - verticalHeight
            )
            results.append((
                target: NSRect(
                    x: left,
                    y: groupY + obstacle.height + windowGap,
                    width: target.width,
                    height: target.height
                ),
                obstacle: NSRect(
                    x: left,
                    y: groupY,
                    width: obstacle.width,
                    height: obstacle.height
                )
            ))
            results.append((
                target: NSRect(
                    x: left,
                    y: groupY,
                    width: target.width,
                    height: target.height
                ),
                obstacle: NSRect(
                    x: left,
                    y: groupY + target.height + windowGap,
                    width: obstacle.width,
                    height: obstacle.height
                )
            ))
        }
        return results
    }

    private static func fitted(_ frame: NSRect, within bounds: NSRect) -> NSRect {
        var result: NSRect = frame
        result.size.width = min(result.width, bounds.width)
        result.size.height = min(result.height, bounds.height)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }

    private static func overlapArea(of frame: NSRect, with obstacles: [NSRect]) -> CGFloat {
        obstacles.reduce(0) { total, obstacle in
            let spacedObstacle: NSRect = obstacle.insetBy(dx: -windowGap, dy: -windowGap)
            let intersection: NSRect = frame.intersection(spacedObstacle)
            return total + max(intersection.width, 0) * max(intersection.height, 0)
        }
    }

    private static func movementDistance(from original: NSRect, to candidate: NSRect) -> CGFloat {
        abs(original.minX - candidate.minX) + abs(original.minY - candidate.minY)
    }
}

private final class RegisteredApplicationWindow {
    weak var window: NSWindow?
    let role: ManagedApplicationWindowRole

    init(window: NSWindow, role: ManagedApplicationWindowRole) {
        self.window = window
        self.role = role
    }
}
