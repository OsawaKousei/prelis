import AppKit

/// Keep clipboard contents in memory only, including non-text representations.
/// Refuse to overwrite an unrelated copy made while the test is running.
final class MacClipboard {
    private let board = NSPasteboard.general
    private let original: [NSPasteboardItem]
    private var ownedChangeCount: Int
    private var expectedTexts = Set<String>()

    init() throws {
        let count = board.changeCount
        var items: [NSPasteboardItem] = []
        for item in board.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type), copy.setData(data, forType: type) else {
                    throw E2EError.condition("Cannot preserve every clipboard representation")
                }
            }
            items.append(copy)
        }
        guard board.changeCount == count else {
            throw E2EError.condition("Clipboard changed while it was being preserved")
        }
        original = items
        ownedChangeCount = count
    }

    func writeText(_ text: String) throws {
        guard board.changeCount == ownedChangeCount else {
            throw E2EError.condition("Clipboard changed outside the test; refusing to overwrite it")
        }
        expectedTexts.insert(text)
        board.clearContents()
        ownedChangeCount = board.changeCount
        guard board.setString(text, forType: .string) else {
            throw E2EError.condition("Cannot put the test input on the clipboard")
        }
        ownedChangeCount = board.changeCount
    }

    func expectCopy(of text: String) { expectedTexts.insert(text) }

    func contains(_ text: String) -> Bool { board.string(forType: .string) == text }

    func restore() throws {
        let count = board.changeCount
        if count != ownedChangeCount {
            guard let text = board.string(forType: .string), expectedTexts.contains(text) else {
                throw E2EError.condition("Clipboard changed outside the test; leaving the newer contents intact")
            }
        }
        guard board.changeCount == count else {
            throw E2EError.condition("Clipboard changed during restoration; leaving it intact")
        }
        board.clearContents()
        ownedChangeCount = board.changeCount
        if !original.isEmpty, !board.writeObjects(original) {
            throw E2EError.condition("Cannot restore the original clipboard")
        }
        ownedChangeCount = board.changeCount
    }
}
