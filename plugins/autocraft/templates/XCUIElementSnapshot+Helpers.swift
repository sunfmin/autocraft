import XCTest

extension XCUIElementSnapshot {
    /// Check if a descendant with the given accessibility identifier exists in the snapshot.
    /// This is instant (pure CPU, no IPC) since the snapshot is an in-memory tree.
    func hasDescendant(id: String, type: XCUIElement.ElementType = .any) -> Bool {
        descendants(matching: type).contains { $0.identifier == id }
    }

    /// Check if a descendant with a label containing the given text exists.
    func hasDescendant(labelContaining text: String, type: XCUIElement.ElementType = .any) -> Bool {
        descendants(matching: type).contains { $0.label.contains(text) }
    }

    /// Find a descendant's label by accessibility identifier.
    /// Returns nil if not found.
    func label(for id: String, type: XCUIElement.ElementType = .any) -> String? {
        descendants(matching: type).first { $0.identifier == id }?.label
    }
}
