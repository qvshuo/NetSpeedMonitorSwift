import Foundation
import SystemConfiguration

actor NetworkInterfaceResolver {
    private var store: SCDynamicStore?

    func resolveDefaultInterface() -> String? {
        if store == nil {
            store = SCDynamicStoreCreate(nil, "NetSpeedMonitorSwift" as CFString, nil, nil)
        }
        guard let store else {
            let message = String(validatingCString: SCErrorString(SCError())) ?? "unknown error"
            logger.warning("resolveDefaultInterface failed to create dynamic store: \(message)")
            return nil
        }

        for entity in [kSCEntNetIPv4, kSCEntNetIPv6] {
            let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, entity)
            guard let value = SCDynamicStoreCopyValue(store, key) as? [String: Any],
                  let name = value[kSCDynamicStorePropNetPrimaryInterface as String] as? String else {
                continue
            }
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty { return trimmedName }
        }
        return nil
    }
}
