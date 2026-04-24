import Foundation
import SystemConfiguration

actor NetworkInterfaceResolver {
    func resolveDefaultInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "NetSpeedMonitorSwift" as CFString, nil, nil) else {
            let message = String(validatingCString: SCErrorString(SCError())) ?? "unknown error"
            logger.warning("resolveDefaultInterface failed to create dynamic store: \(message)")
            return nil
        }

        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4)
        guard let value = SCDynamicStoreCopyValue(store, key) as? [String: Any] else {
            logger.warning("resolveDefaultInterface did not find State:/Network/Global/IPv4")
            return nil
        }

        guard let interfaceName = value[kSCDynamicStorePropNetPrimaryInterface as String] as? String else {
            logger.warning("resolveDefaultInterface missing PrimaryInterface in State:/Network/Global/IPv4")
            return nil
        }

        let trimmedName = interfaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }
}
