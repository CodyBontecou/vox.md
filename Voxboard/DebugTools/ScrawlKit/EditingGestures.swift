// Vendored from ScrawlKit (https://github.com/kitlangton/scrawl, Sources/ScrawlKit)
// at v0.3.14 (28aafd4788e21e42a474209102990fe359b1829a). DEBUG builds only: Release and App Store builds compile none of it.
// Local changes, needed because the Vox.md target defaults to MainActor isolation and
// extracts SwiftUI string literals into its catalog:
//   * top-level declarations ScrawlKit leaves nonisolated are marked `nonisolated`;
//   * on-screen and accessibility strings use `Text(verbatim:)`.
// To update, re-copy the sources and reapply both. MIT license: ScrawlKit+License.swift.

#if DEBUG
#if os(iOS)
  import ObjectiveC
  import os
  import UIKit

  /// Turns off iOS's three-finger text-editing gestures (undo, redo, cut, copy, paste, and the
  /// Undo · Cut · Copy · Redo bar) in the app's windows, so ScrawlKit's three-finger long press
  /// doesn't also open that bar while a text field is focused.
  ///
  /// UIKit's `UIUndoGestureInteraction` lets those gestures begin only if no responder from the
  /// first responder up the `nextResponder` chain returns `.none` from
  /// `editingInteractionConfiguration` (`privateEditingInteractionOptions` walks the whole chain;
  /// one `.none` disables all five three-finger recognizers). A text field's chain always reaches
  /// its `UIWindow`, so `UIWindow` answering `.none` is enough. `UIWindow` doesn't implement the
  /// property itself, so a method is added to it (no swizzling); app subclasses that override it
  /// keep their own answer, and ScrawlKit's `OverlayWindow` is left alone.
  ///
  /// The trade-off: while active, three-finger undo, redo, cut, copy, and paste don't work in the
  /// app. It's only active on paired devices, with a three-finger trigger installed, while
  /// `Scrawl.shared.suppressesSystemEditingGestures` is true. Nothing is added to `UIWindow`
  /// until it first becomes active; afterwards the added method defers to `UIResponder`'s.
  nonisolated enum SystemEditingGestures {
    private static let isSuppressing = OSAllocatedUnfairLock(initialState: false)

    @MainActor
    static func setSuppressed(_ suppressed: Bool) {
      if suppressed { _ = installed }
      isSuppressing.withLock { $0 = suppressed }
    }

    private static let installed: Bool = {
      typealias Getter = @convention(c) (AnyObject, Selector) -> Int
      let selector = #selector(getter: UIResponder.editingInteractionConfiguration)
      guard let method = class_getInstanceMethod(UIWindow.self, selector),
            let inheritedIMP = class_getMethodImplementation(UIView.self, selector)
      else { return false }
      // If a later iOS gives UIWindow its own implementation, wrap that one instead.
      let ownIMP = method_getImplementation(method)
      let windowHasOwn = ownIMP != inheritedIMP
      let block: @convention(block) (AnyObject) -> Int = { window in
        if isSuppressing.withLock({ $0 }), !(window is OverlayWindow) {
          return UIEditingInteractionConfiguration.none.rawValue
        }
        let original = windowHasOwn ? ownIMP : class_getMethodImplementation(UIView.self, selector) ?? inheritedIMP
        return unsafeBitCast(original, to: Getter.self)(window, selector)
      }
      let imp = imp_implementationWithBlock(block)
      if windowHasOwn {
        method_setImplementation(method, imp)
        return true
      }
      return class_addMethod(UIWindow.self, selector, imp, method_getTypeEncoding(method))
    }()
  }
#endif
#endif
