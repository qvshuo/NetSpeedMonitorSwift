import Darwin
import Foundation

struct InterfaceRate {
    let name: String
    let inputBytesPerSecond: Double
    let outputBytesPerSecond: Double

    var totalBytesPerSecond: Double {
        inputBytesPerSecond + outputBytesPerSecond
    }
}

extension [InterfaceRate] {
    func mostActive() -> InterfaceRate? {
        filter { $0.totalBytesPerSecond > 0 }
            .max { $0.totalBytesPerSecond < $1.totalBytesPerSecond }
    }

    func first(named name: String) -> InterfaceRate? {
        first { $0.name == name }
    }
}

private struct InterfaceSnapshot {
    let timestamp: ContinuousClock.Instant
    let inputBytes: UInt32
    let outputBytes: UInt32
    let isUp: Bool
}

struct NetworkRateSampler {
    private let clock = ContinuousClock()
    private var previousSnapshots: [String: InterfaceSnapshot] = [:]

    mutating func sample() -> [InterfaceRate] {
        let snapshots = readSnapshots()
        defer {
            if !snapshots.isEmpty {
                previousSnapshots = snapshots
            }
        }

        return snapshots.map { name, snapshot in
            rate(name: name, current: snapshot, previous: previousSnapshots[name])
        }
    }

    private func readSnapshots() -> [String: InterfaceSnapshot] {
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0, let firstAddress = interfaceAddresses else {
            return [:]
        }

        defer {
            freeifaddrs(interfaceAddresses)
        }

        var snapshots: [String: InterfaceSnapshot] = [:]
        var currentAddress: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let address = currentAddress {
            let interface = address.pointee
            defer {
                currentAddress = interface.ifa_next
            }

            guard let interfaceAddress = interface.ifa_addr,
                  interfaceAddress.pointee.sa_family == UInt8(AF_LINK),
                  (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
                  let interfaceData = interface.ifa_data else {
                continue
            }

            let data = interfaceData.assumingMemoryBound(to: if_data.self).pointee
            snapshots[String(cString: interface.ifa_name)] = InterfaceSnapshot(
                timestamp: clock.now,
                inputBytes: data.ifi_ibytes,
                outputBytes: data.ifi_obytes,
                isUp: (interface.ifa_flags & UInt32(IFF_UP)) != 0
            )
        }

        return snapshots
    }

    private func rate(name: String, current: InterfaceSnapshot, previous: InterfaceSnapshot?) -> InterfaceRate {
        guard let previous, current.isUp else {
            return InterfaceRate(name: name, inputBytesPerSecond: 0.0, outputBytesPerSecond: 0.0)
        }

        let elapsed = previous.timestamp.duration(to: current.timestamp)
        let deltaSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        guard deltaSeconds <= 60.0 else {
            return InterfaceRate(name: name, inputBytesPerSecond: 0.0, outputBytesPerSecond: 0.0)
        }

        let deltaInputBytes = delta(current: current.inputBytes, previous: previous.inputBytes)
        let deltaOutputBytes = delta(current: current.outputBytes, previous: previous.outputBytes)
        let divisor = deltaSeconds + 1e-3

        return InterfaceRate(
            name: name,
            inputBytesPerSecond: Double(deltaInputBytes) / divisor,
            outputBytesPerSecond: Double(deltaOutputBytes) / divisor
        )
    }

    private func delta(current: UInt32, previous: UInt32) -> Int64 {
        if current < previous {
            return Int64(current) + Int64(UInt32.max) + 1 - Int64(previous)
        }

        return Int64(current) - Int64(previous)
    }
}
