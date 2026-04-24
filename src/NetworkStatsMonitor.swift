import Darwin
import Foundation

struct InterfaceRate {
    let name: String
    let inputBytesPerSecond: Double
    let outputBytesPerSecond: Double
}

private struct InterfaceSnapshot {
    let timestamp: ContinuousClock.Instant
    let inputBytes: UInt32
    let outputBytes: UInt32
    let isUp: Bool
}

struct NetworkRateSampler {
    private let clock = ContinuousClock()
    private var previousSnapshot: InterfaceSnapshot?
    private var previousInterfaceName: String?

    mutating func update(interfaceName: String?) -> InterfaceRate? {
        guard let interfaceName, !interfaceName.isEmpty else {
            previousSnapshot = nil
            previousInterfaceName = nil
            return nil
        }

        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0, let firstAddress = interfaceAddresses else {
            return nil
        }

        defer {
            freeifaddrs(interfaceAddresses)
        }

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

            let currentInterfaceName = String(cString: interface.ifa_name)
            guard currentInterfaceName == interfaceName else {
                continue
            }

            let data = interfaceData.assumingMemoryBound(to: if_data.self).pointee
            let snapshot = InterfaceSnapshot(
                timestamp: clock.now,
                inputBytes: data.ifi_ibytes,
                outputBytes: data.ifi_obytes,
                isUp: (interface.ifa_flags & UInt32(IFF_UP)) != 0
            )

            let rate = makeRate(name: currentInterfaceName, currentSnapshot: snapshot)
            previousSnapshot = snapshot
            previousInterfaceName = currentInterfaceName
            return rate
        }

        previousSnapshot = nil
        previousInterfaceName = nil
        return nil
    }

    private mutating func makeRate(name: String, currentSnapshot: InterfaceSnapshot) -> InterfaceRate {
        guard previousInterfaceName == name,
              let previousSnapshot,
              currentSnapshot.isUp else {
            return InterfaceRate(name: name, inputBytesPerSecond: 0.0, outputBytesPerSecond: 0.0)
        }

        let elapsed = previousSnapshot.timestamp.duration(to: currentSnapshot.timestamp)
        let deltaSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        guard deltaSeconds <= 60.0 else {
            return InterfaceRate(name: name, inputBytesPerSecond: 0.0, outputBytesPerSecond: 0.0)
        }

        let deltaInputBytes = delta(current: currentSnapshot.inputBytes, previous: previousSnapshot.inputBytes)
        let deltaOutputBytes = delta(current: currentSnapshot.outputBytes, previous: previousSnapshot.outputBytes)
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
