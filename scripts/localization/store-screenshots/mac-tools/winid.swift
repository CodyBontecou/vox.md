import CoreGraphics
import Foundation
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
var best: (Int, Double, String) = (0, 0, "")
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
  let b = w[kCGWindowBounds as String] as! [String: Double]
  let area = b["Width"]! * b["Height"]!
  if area > best.1 { best = (w[kCGWindowNumber as String] as! Int, area, "\(Int(b["Width"]!))x\(Int(b["Height"]!))") }
}
print(best.0, best.2)
