import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().map { Double($0)! }
let from = CGPoint(x: a[0], y: a[1]), to = CGPoint(x: a[2], y: a[3])
func post(_ t: CGEventType, _ p: CGPoint) {
  CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
}
post(.mouseMoved, from); usleep(150_000)
post(.leftMouseDown, from); usleep(150_000)
for i in 1...20 { let f = Double(i)/20; post(.leftMouseDragged, CGPoint(x: from.x + (to.x-from.x)*f, y: from.y)); usleep(20_000) }
post(.leftMouseUp, to)
