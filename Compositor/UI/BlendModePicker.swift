import SwiftUI
import AppKit

struct BlendModePicker: NSViewRepresentable {
    let session: EditorSession
    func makeCoordinator() -> Coordinator { Coordinator(session: session) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        // Grouped as Photoshop groups them — darkening, lightening, contrast, comparative, component —
        // with a line between, so a long list stays readable.
        for (index, group) in LayerBlendMode.groups.enumerated() {
            if index > 0 { button.menu?.addItem(.separator()) }
            // The item's title is the localized name; its tag carries the mode, so the selection is
            // never read back out of a title.
            for mode in group {
                button.addItem(withTitle: mode.displayName)
                button.lastItem?.tag = mode.menuTag
            }
        }
        button.menu?.delegate = context.coordinator
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        button.setAccessibilityLabel(String(localized: "Blend mode"))
        // A capsule like the SwiftUI buttons and menus (`roundedControls`), which don't reach this AppKit pop-up.
        button.borderShape = .capsule
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        button.isEnabled = session.canEditAppearance
        if !context.coordinator.tracking,
           let item = button.menu?.item(withTag: (session.activeLayer?.blendMode ?? .normal).menuTag) {
            button.select(item)
        }
    }
    static func dismantleNSView(_ button: NSPopUpButton, coordinator: Coordinator) {
        if coordinator.tracking { coordinator.session.previewBlendMode(nil, for: nil) }
        button.menu?.delegate = nil
    }
    final class Coordinator: NSObject, NSMenuDelegate {
        let session: EditorSession
        var tracking = false
        private var layerID: UUID?
        private var highlightedMode: LayerBlendMode?
        init(session: EditorSession) { self.session = session }
        func menuWillOpen(_ menu: NSMenu) {
            tracking = true
            layerID = session.activeLayerID
            highlightedMode = nil
        }
        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            // AppKit briefly reports no highlighted item while dismissing the menu.
            // Keep the last preview alive until the selection action has committed so
            // the canvas never flashes back to the layer's previous mode.
            guard let mode = layerBlendMode(for: item) else { return }
            highlightedMode = mode
            session.previewBlendMode(mode, for: layerID)
        }
        func menuDidClose(_ menu: NSMenu) {
            tracking = false
            // A chosen item's action runs as the menu finishes closing. Clearing on the
            // next turn lets that action replace the preview with the committed mode;
            // when the menu was cancelled, this simply restores the original mode.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.tracking else { return }
                self.session.previewBlendMode(nil, for: nil)
            }
        }
        @objc func choose(_ button: NSPopUpButton) {
            guard session.activeLayerID == layerID,
                  let mode = highlightedMode ?? layerBlendMode(for: button.selectedItem) else { return }
            session.setLayerBlendMode(mode)
            if let item = button.menu?.item(withTag: mode.menuTag) { button.select(item) }
            highlightedMode = nil
            session.refreshCanvasPreview?()
        }
    }
}

private extension LayerBlendMode {
    /// The pop-up item's tag: the mode's place among the cases, offset by one so a separator's
    /// default tag of zero matches no mode.
    var menuTag: Int { (LayerBlendMode.allCases.firstIndex(of: self) ?? 0) + 1 }
}

/// The mode an item stands for, from its tag rather than its (localized) title.
private func layerBlendMode(for item: NSMenuItem?) -> LayerBlendMode? {
    guard let item, LayerBlendMode.allCases.indices.contains(item.tag - 1) else { return nil }
    return LayerBlendMode.allCases[item.tag - 1]
}
