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

    // Hysteresis: keep the current interface until a challenger wins
    // `dwellTicks` consecutive samples; switch quickly once it goes idle.
    private static let dwellTicks = 3
    private static let idleSwitchTicks = 1

    @ObservationIgnored private var currentInterface: String?
    @ObservationIgnored private var challengerName: String?
    @ObservationIgnored private var challengerStreak = 0

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
        currentInterface = nil
        challengerName = nil
        challengerStreak = 0
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

        guard let candidate = rates.mostActive() else {
            await presentFallbackInterface(from: rates)
            return
        }

        guard candidate.name != currentInterface else {
            challengerName = nil
            challengerStreak = 0
            present(candidate)
            return
        }

        let currentRate = currentInterface.flatMap { rates.first(named: $0) }
        let currentIsIdle = currentRate.map { $0.totalBytesPerSecond <= 0 } ?? true

        // A challenger must win `dwellTicks` consecutive samples before replacing
        // the current interface; a win by any other interface resets the streak.
        if candidate.name == challengerName {
            challengerStreak += 1
        } else {
            challengerName = candidate.name
            challengerStreak = 1
        }

        let requiredStreak = currentIsIdle ? Self.idleSwitchTicks : Self.dwellTicks
        if challengerStreak >= requiredStreak {
            switchLock(to: candidate)
        }

        present(currentRate ?? candidate)
    }

    private func switchLock(to interface: InterfaceRate) {
        currentInterface = interface.name
        challengerName = nil
        challengerStreak = 0
    }

    private func presentFallbackInterface(from rates: [InterfaceRate]) async {
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

        let inMetric = formattedDownload.metric
        let outMetric = formattedUpload.metric
        let deltaIn = String(format: "%.6f", formattedDownload.value)
        let deltaOut = String(format: "%.6f", formattedUpload.value)
        logger.debug(
            "\(interfaceName, privacy: .public): in \(deltaIn) \(inMetric)/s, out \(deltaOut) \(outMetric)/s"
        )
    }

    private func formatSpeed(_ speed: Double) -> (text: String, value: Double, metric: String) {
        var value = speed
        // Leading space in each metric keeps the unit column aligned.
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
