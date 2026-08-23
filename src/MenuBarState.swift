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

    init() {
        start()
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
        await refreshStats()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                break
            }

            await refreshStats()
        }
    }

    private func refreshStats() async {
        let rates = networkRateSampler.sample()

        if let rate = rates.mostActive() {
            present(rate)
            return
        }

        if let resolvedInterface = await interfaceResolver.resolveDefaultInterface() {
            present(
                rates.first(named: resolvedInterface)
                    ?? InterfaceRate(name: resolvedInterface, inputBytesPerSecond: 0.0, outputBytesPerSecond: 0.0)
            )
            return
        }

        updatePresentation(interfaceName: "Unavailable", downloadSpeed: 0.0, uploadSpeed: 0.0)
    }

    private func present(_ rate: InterfaceRate) {
        updatePresentation(
            interfaceName: rate.name,
            downloadSpeed: rate.inputBytesPerSecond,
            uploadSpeed: rate.outputBytesPerSecond
        )
    }

    private func updatePresentation(interfaceName: String, downloadSpeed: Double, uploadSpeed: Double) {
        let formattedDownload = formatSpeed(downloadSpeed)
        let formattedUpload = formatSpeed(uploadSpeed)

        presentation = MenuBarPresentation(
            interfaceName: interfaceName,
            uploadText: formattedUpload.text,
            downloadText: formattedDownload.text
        )

        logger.debug(
            "interface: \(interfaceName, privacy: .public), deltaIn: \(String(format: "%.6f", formattedDownload.value)) \(formattedDownload.metric)/s, deltaOut: \(String(format: "%.6f", formattedUpload.value)) \(formattedUpload.metric)/s"
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
