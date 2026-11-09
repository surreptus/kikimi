import LangCore
import Observation
import SwiftUI

/// The app's text size, where views can watch it: a view that builds a font through `Theme` reads `scale`, so SwiftUI
/// redraws it when the setting changes. Saved on this Mac.
@Observable
final class TextScaleModel {
    nonisolated(unsafe) static let shared = TextScaleModel()

    var scale: TextScale = TextScale.stored() {
        didSet { scale.store() }
    }
}
