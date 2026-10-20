import Foundation

/// Free-space estimates for the destination volume, checked before an encode starts.
public enum DiskSpace {
    /// Bytes an encode may need: an MKV keeps an intermediate movie next to the
    /// output while remuxing, so it needs about twice the source; others about once.
    public static func requiredBytes(sourceBytes: Int64, container: ContainerFormat) -> Int64 {
        let factor: Int64 = container == .mkv ? 2 : 1
        let (product, overflow) = max(sourceBytes, 0).multipliedReportingOverflow(by: factor)
        return overflow ? .max : product
    }

    /// Free bytes on the volume holding `folder`, or nil if the system can't say.
    public static func availableCapacity(at folder: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? folder.resourceValues(forKeys: keys) else { return nil }
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values.volumeAvailableCapacity.map(Int64.init)
    }
}
