import Foundation

public enum ClipboardRestorationPolicy {
    public static func shouldRestore(
        currentChangeCount: Int,
        preparedChangeCount: Int
    ) -> Bool {
        currentChangeCount == preparedChangeCount
    }
}
