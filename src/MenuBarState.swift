import AppKit
import Observation

struct MenuBarPresentation {
    var interfaceName: String
    var uploadText: String
    var downloadText: String

    static let empty = MenuBarPresentation(
        interfaceName: "Unavailable",
        uploadText: String(format: "%6.2lf  B/s", 0.0),
        downloadText: String(format: "%6.2lf  B/s", 0.0)
    )

    var iconText: String {
        "↑ \(uploadText)\n↓ \(downloadText)"
    }
}

@MainActor
@Observable
final class MenuBarModel {
    private(set) var presentation = MenuBarPresentation.empty

    @ObservationIgnored private var monitoredInterface: String?
    @ObservationIgnored private var ticksSinceInterfaceRefresh = 0
    @ObservationIgnored private var monitoringTask: Task<Void, Never>?
    @ObservationIgnored private var networkRateSampler = NetworkRateSampler()
    @ObservationIgnored private let interfaceResolver = NetworkInterfaceResolver()

    private let speedMetrics = [" B", "KB", "MB", "GB", "TB"]

    var currentIcon: NSImage {
        MenuBarIconGenerator.generateIcon(presentation: presentation)
    }

    var interfaceDisplayName: String {
        presentation.interfaceName
    }

    func start() {
        guard monitoringTask == nil else {
            return
        }

        logger.info("startMonitoring")
        monitoringTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.runMonitoringLoop()
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        logger.info("stopMonitoring")
    }

    deinit {
        monitoringTask?.cancel()
    }

    private func runMonitoringLoop() async {
        await refreshStats(forceInterfaceRefresh: true)

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                break
            }

            await refreshStats()
        }
    }

    private func refreshStats(forceInterfaceRefresh: Bool = false) async {
        ticksSinceInterfaceRefresh += 1
        await refreshMonitoredInterface(force: forceInterfaceRefresh)

        let rate = networkRateSampler.update(interfaceName: monitoredInterface)
        guard let rate else {
            updatePresentation(
                interfaceName: monitoredInterface ?? "Unavailable",
                downloadSpeed: 0.0,
                uploadSpeed: 0.0
            )
            return
        }

        updatePresentation(
            interfaceName: rate.name,
            downloadSpeed: rate.inputBytesPerSecond,
            uploadSpeed: rate.outputBytesPerSecond
        )
    }

    private func refreshMonitoredInterface(force: Bool = false) async {
        guard force || ticksSinceInterfaceRefresh >= 5 else {
            return
        }

        ticksSinceInterfaceRefresh = 0
        let resolvedInterface = await interfaceResolver.resolveDefaultInterface()
        monitoredInterface = resolvedInterface
        presentation.interfaceName = resolvedInterface ?? "Unavailable"
    }

    private func updatePresentation(interfaceName: String, downloadSpeed: Double, uploadSpeed: Double) {
        let formattedDownload = formatSpeed(downloadSpeed)
        let formattedUpload = formatSpeed(uploadSpeed)

        presentation = MenuBarPresentation(
            interfaceName: interfaceName,
            uploadText: formattedUpload.text,
            downloadText: formattedDownload.text
        )

        logger.info(
            "interface: \(interfaceName), deltaIn: \(String(format: "%.6f", formattedDownload.value)) \(formattedDownload.metric)/s, deltaOut: \(String(format: "%.6f", formattedUpload.value)) \(formattedUpload.metric)/s"
        )
    }

    private func formatSpeed(_ speed: Double) -> (text: String, value: Double, metric: String) {
        var value = speed
        var metric = " B"

        for nextMetric in speedMetrics.dropFirst() {
            if value > 1000.0 {
                value /= 1024.0
                metric = nextMetric
            }
        }

        return (
            text: String(format: "%6.2lf %@/s", value, metric),
            value: value,
            metric: metric
        )
    }
}
