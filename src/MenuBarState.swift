import SwiftUI

@MainActor
final class MenuBarState: NSObject, ObservableObject {
    @Published var menuText = "↑ \(String(format: "%6.2lf", 0)) \(" B")/s\n↓ \(String(format: "%6.2lf", 0)) \(" B")/s"
    @Published var monitoredInterfaceName = "Unavailable"
    
    var currentIcon: NSImage {
        return MenuBarIconGenerator.generateIcon(text: menuText)
    }
    
    private var timer: Timer?
    private var monitoredInterface: String?
    private var ticksSinceInterfaceRefresh = 0
    private var networkStatsMonitor = NetworkStatsMonitor()
    private let interfaceRefreshQueue = DispatchQueue(label: "NetSpeedMonitor.route-refresh")
    
    private var uploadSpeed: Double = 0.0
    private var downloadSpeed: Double = 0.0
    private var uploadMetric: String = " B"
    private var downloadMetric: String = " B"
    private let speedMetrics: [String] = [" B", "KB", "MB", "GB", "TB"]
    
    private func refreshMonitoredInterface(force: Bool = false) {
        if force || ticksSinceInterfaceRefresh >= 5 {
            ticksSinceInterfaceRefresh = 0
            interfaceRefreshQueue.async {
                let resolvedInterface = Self.resolveDefaultInterface()
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    self.monitoredInterface = resolvedInterface
                    self.monitoredInterfaceName = resolvedInterface ?? "Unavailable"
                }
            }
        }
    }
    
    private func startTimer() {
        let timer = Timer(timeInterval: 1.0, target: self, selector: #selector(handleTimer), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
        logger.info("startTimer")
    }

    @objc private func handleTimer() {
        refreshStats()
    }

    private func refreshStats() {
        ticksSinceInterfaceRefresh += 1
        refreshMonitoredInterface()
        let rate = networkStatsMonitor.update(interfaceName: monitoredInterface)

        guard let rate else {
            monitoredInterfaceName = monitoredInterface ?? "Unavailable"
            updateMenuText(downloadSpeed: 0.0, uploadSpeed: 0.0)
            return
        }

        monitoredInterfaceName = rate.name
        updateMenuText(downloadSpeed: rate.inputBytesPerSecond, uploadSpeed: rate.outputBytesPerSecond)
        logger.info(
            "interface: \(rate.name), deltaIn: \(String(format: "%.6f", self.downloadSpeed)) \(self.downloadMetric)/s, deltaOut: \(String(format: "%.6f", self.uploadSpeed)) \(self.uploadMetric)/s"
        )
    }

    nonisolated private static func resolveDefaultInterface() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            logger.warning("resolveDefaultInterface failed to start route: \(error.localizedDescription)")
            return nil
        }

        process.waitUntilExit()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            if errorOutput.isEmpty {
                logger.warning("resolveDefaultInterface route exited with status \(process.terminationStatus)")
            } else {
                logger.warning("resolveDefaultInterface route exited with status \(process.terminationStatus), stderr: \(errorOutput)")
            }
            return nil
        }

        guard let output = String(data: outputData, encoding: .utf8) else {
            logger.warning("resolveDefaultInterface failed to decode route output")
            return nil
        }

        for line in output.split(separator: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard trimmedLine.hasPrefix("interface:") else {
                continue
            }

            let interfaceName = trimmedLine.replacingOccurrences(of: "interface:", with: "")
                .trimmingCharacters(in: .whitespaces)
            return interfaceName.isEmpty ? nil : interfaceName
        }

        return nil
    }

    private func updateMenuText(downloadSpeed: Double, uploadSpeed: Double) {
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.downloadMetric = " B"
        self.uploadMetric = " B"

        for metric in speedMetrics.dropFirst() {
            if self.downloadSpeed > 1000.0 {
                self.downloadSpeed /= 1024.0
                self.downloadMetric = metric
            }
            if self.uploadSpeed > 1000.0 {
                self.uploadSpeed /= 1024.0
                self.uploadMetric = metric
            }
        }

        menuText = "↑ \(String(format: "%6.2lf", self.uploadSpeed)) \(self.uploadMetric)/s\n↓ \(String(format: "%6.2lf", self.downloadSpeed)) \(self.downloadMetric)/s"
    }
    
    private func stopTimer() {
        self.timer?.invalidate()
        self.timer = nil
        logger.info("stopTimer")
    }
    
    override init() {
        super.init()
        DispatchQueue.main.async {
            self.refreshMonitoredInterface(force: true)
            self.startTimer()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
