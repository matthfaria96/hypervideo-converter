import Foundation

/// Names of the private folders an encode works in, next to its output.
/// New folders are `.hypervideo-<jobID>-<uuid>`; older builds wrote `.hypervideo-<uuid>`.
public enum WorkFolder {
    public static let prefix = ".hypervideo-"
    private static let uuidLength = 36

    /// A fresh folder name, tagged with `jobID` when given.
    public static func name(jobID: UUID?) -> String {
        guard let jobID else { return prefix + UUID().uuidString }
        return "\(prefix)\(jobID.uuidString)-\(UUID().uuidString)"
    }

    /// The job that owns a folder named `name`, nil for legacy or unrelated names.
    public static func jobID(fromName name: String) -> UUID? {
        guard name.hasPrefix(prefix) else { return nil }
        let rest = name.dropFirst(prefix.count)
        guard rest.count == uuidLength * 2 + 1 else { return nil }
        let head = rest.prefix(uuidLength)
        let tail = rest.dropFirst(uuidLength)
        guard tail.first == "-", UUID(uuidString: String(tail.dropFirst())) != nil else { return nil }
        return UUID(uuidString: String(head))
    }

    /// True for work folders in either the new or the legacy shape.
    public static func isWorkFolder(name: String) -> Bool {
        guard name.hasPrefix(prefix) else { return false }
        if jobID(fromName: name) != nil { return true }
        return UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
    }
}
