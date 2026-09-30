import Darwin
import Foundation

/// Per-interface network throughput in bytes per second.
struct InterfaceRate {
    let name: String
    let inputBytesPerSecond: Double
    let outputBytesPerSecond: Double

    var totalBytesPerSecond: Double {
        inputBytesPerSecond + outputBytesPerSecond
    }
}

extension [InterfaceRate] {
    /// Returns the interface with the highest total throughput, or nil if all are idle.
    func mostActive() -> InterfaceRate? {
        filter { $0.totalBytesPerSecond > 0 }
            .max { $0.totalBytesPerSecond < $1.totalBytesPerSecond }
    }

    func first(named name: String) -> InterfaceRate? {
        first { $0.name == name }
    }
}

/// An empty success means no matching interfaces; failure means the read was unavailable.
enum NetworkSampleResult {
    case success([InterfaceRate])
    case failure
}

private struct InterfaceSnapshot {
    let timestamp: ContinuousClock.Instant
    let inputBytes: UInt64
    let outputBytes: UInt64
    let isUp: Bool
}

/// Reads 64-bit kernel counters to avoid the 4 GiB wraparound of `getifaddrs`.
actor NetworkRateSampler {
    private let clock = ContinuousClock()
    private var previousSnapshots: [String: InterfaceSnapshot] = [:]

    // Reuse the allocation across samples.
    nonisolated(unsafe) private var linkBuffer: UnsafeMutableRawPointer?
    private var linkBufferSize = 0

    func sample() -> NetworkSampleResult {
        autoreleasepool {
            guard let snapshots = readSnapshots() else { return .failure }
            // Preserve history on failure; replace it after calculating successful deltas.
            defer { previousSnapshots = snapshots }
            return .success(snapshots.map { name, snapshot in
                rate(name: name, current: snapshot, previous: previousSnapshots[name])
            })
        }
    }

    /// Makes the next successful sample establish a fresh baseline.
    func resetBaselines() {
        previousSnapshots.removeAll(keepingCapacity: true)
    }

    nonisolated deinit {
        if let buffer = linkBuffer {
            free(buffer)
        }
    }

    // MARK: - Kernel counters

    private func readSnapshots() -> [String: InterfaceSnapshot]? {
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFALLDATA, 0, IFDATA_GENERAL]

        for attempt in 0..<2 {
            if linkBuffer == nil {
                guard resizeBuffer(for: &mib) else { return nil }
            }
            guard let buffer = linkBuffer else { return nil }
            var size = linkBufferSize
            if sysctl(&mib, 6, buffer, &size, nil, 0) == 0 {
                return parseSnapshots(buffer, size)
            }
            let code = errno
            guard code == ENOMEM, attempt == 0 else {
                return nil
            }
            guard resizeBuffer(for: &mib) else { return nil }
        }
        return nil
    }

    private func resizeBuffer(for mib: inout [Int32]) -> Bool {
        var needed = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &needed, nil, 0) == 0 else {
            return false
        }
        // Leave room for interfaces appearing between sizing and fetching.
        let target = needed + needed / 4 + 1024
        guard let buffer = realloc(linkBuffer, target) else { return false }
        linkBuffer = buffer
        linkBufferSize = target
        return true
    }

    private func parseSnapshots(_ buffer: UnsafeMutableRawPointer, _ size: Int) -> [String: InterfaceSnapshot]? {
        let recordSize = MemoryLayout<ifmibdata>.size
        guard recordSize > 0, size % recordSize == 0 else {
            return nil
        }

        var snapshots: [String: InterfaceSnapshot] = [:]
        snapshots.reserveCapacity(size / recordSize)
        var offset = 0
        while offset + recordSize <= size {
            defer { offset += recordSize }
            let record = buffer.loadUnaligned(fromByteOffset: offset, as: ifmibdata.self)
            let name = withUnsafeBytes(of: record.ifmd_name) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            guard !name.isEmpty else { continue }

            let flags = Int32(bitPattern: record.ifmd_flags)
            guard flags & IFF_LOOPBACK == 0 else { continue }
            guard name.hasPrefix("en") || name.hasPrefix("utun") else { continue }

            snapshots[name] = InterfaceSnapshot(
                timestamp: clock.now,
                inputBytes: record.ifmd_data.ifi_ibytes,
                outputBytes: record.ifmd_data.ifi_obytes,
                isUp: flags & IFF_UP != 0
            )
        }
        return snapshots
    }

    // MARK: - Rate calculation

    private func rate(name: String, current: InterfaceSnapshot, previous: InterfaceSnapshot?) -> InterfaceRate {
        guard let previous, current.isUp else {
            return InterfaceRate(name: name, inputBytesPerSecond: 0.0, outputBytesPerSecond: 0.0)
        }

        let elapsed = previous.timestamp.duration(to: current.timestamp)
        let deltaSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        // Reject invalid intervals and stale history, such as a sleep gap.
        guard deltaSeconds > 0, deltaSeconds <= 60.0 else {
            return InterfaceRate(name: name, inputBytesPerSecond: 0.0, outputBytesPerSecond: 0.0)
        }

        let deltaInputBytes = delta(current: current.inputBytes, previous: previous.inputBytes)
        let deltaOutputBytes = delta(current: current.outputBytes, previous: previous.outputBytes)

        return InterfaceRate(
            name: name,
            inputBytesPerSecond: Double(deltaInputBytes) / deltaSeconds,
            outputBytesPerSecond: Double(deltaOutputBytes) / deltaSeconds
        )
    }

    /// Treats a decreasing counter as a reset.
    private func delta(current: UInt64, previous: UInt64) -> UInt64 {
        if current < previous {
            return 0
        }
        return current - previous
    }
}
