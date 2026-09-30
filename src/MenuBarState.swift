import AppKit
import Observation

struct MenuBarPresentation: Equatable {
    var interfaceName: String
    var uploadText: String
    var downloadText: String
    var samplingFailed = false

    static let empty = MenuBarPresentation(
        interfaceName: "Unavailable",
        uploadText: String(format: "%6.2lf  B/s", 0.0),
        downloadText: String(format: "%6.2lf  B/s", 0.0)
    )

    var iconText: String {
        "↑ \(uploadText)\n↓ \(downloadText)"
    }
}

/// Selects a network interface and publishes its throughput.
@MainActor
@Observable
final class MenuBarModel {
    private(set) var presentation = MenuBarPresentation.empty
    private(set) var currentIcon = MenuBarIconGenerator.generateIcon(presentation: .empty)

    @ObservationIgnored private var monitoringTask: Task<Void, Never>?
    @ObservationIgnored private let networkRateSampler = NetworkRateSampler()
    @ObservationIgnored private let interfaceResolver = NetworkInterfaceResolver()

    private static let dwellTicks = 3
    private static let idleSwitchTicks = 1

    // Delay between completed samples.
    private static let samplingInterval: TimeInterval = 1.0

    @ObservationIgnored private var currentInterface: String?
    @ObservationIgnored private var challengerName: String?
    @ObservationIgnored private var challengerStreak = 0

    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

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
        let sampler = networkRateSampler
        monitoringTask = Task { [weak self] in
            await sampler.resetBaselines()
            while !Task.isCancelled {
                let result = await sampler.sample()
                guard !Task.isCancelled, self != nil else { return }
                await self?.refreshStats(from: result)
                do {
                    try await Task.sleep(for: .seconds(Self.samplingInterval))
                } catch {
                    return
                }
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleWake()
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        removeWakeObserver()
        currentInterface = nil
        challengerName = nil
        challengerStreak = 0
        logger.info("stopMonitoring")
    }

    isolated deinit {
        monitoringTask?.cancel()
        removeWakeObserver()
    }

    private func removeWakeObserver() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func refreshStats(from result: NetworkSampleResult) async {
        guard !Task.isCancelled else { return }
        guard case .success(let rates) = result else {
            challengerName = nil
            challengerStreak = 0
            publish(MenuBarPresentation(
                interfaceName: presentation.interfaceName,
                uploadText: "    --",
                downloadText: "    --",
                samplingFailed: true
            ))
            return
        }

        guard let candidate = rates.mostActive() else {
            challengerName = nil
            challengerStreak = 0
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

        // Require consecutive wins to prevent flapping; switch immediately if idle.
        if candidate.name == challengerName {
            challengerStreak += 1
        } else {
            challengerName = candidate.name
            challengerStreak = 1
        }

        let requiredStreak = currentIsIdle ? Self.idleSwitchTicks : Self.dwellTicks
        if challengerStreak >= requiredStreak {
            switchLock(to: candidate)
            present(candidate)
            return
        }

        present(currentRate ?? candidate)
    }

    private func handleWake() async {
        guard monitoringTask != nil else { return }
        await networkRateSampler.resetBaselines()
        challengerName = nil
        challengerStreak = 0
        logger.info("System woke from sleep, reset baselines")
    }

    private func switchLock(to interface: InterfaceRate) {
        currentInterface = interface.name
        challengerName = nil
        challengerStreak = 0
    }

    private func presentFallbackInterface(from rates: [InterfaceRate]) async {
        let resolvedInterface = await interfaceResolver.resolveDefaultInterface()
        guard !Task.isCancelled else { return }
        currentInterface = resolvedInterface
        if let resolvedInterface {
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
        publish(MenuBarPresentation(
            interfaceName: interfaceName,
            uploadText: Self.formatSpeed(uploadSpeed),
            downloadText: Self.formatSpeed(downloadSpeed)
        ))
        logger.debug("\(interfaceName, privacy: .public): in \(downloadSpeed) B/s, out \(uploadSpeed) B/s")
    }

    private func publish(_ next: MenuBarPresentation) {
        guard next != presentation else { return }
        if next.iconText != presentation.iconText {
            currentIcon = MenuBarIconGenerator.generateIcon(presentation: next)
        }
        presentation = next
    }

    /// Uses 1024-byte scaling with conventional KB/MB/GB/TB labels.
    private static func formatSpeed(_ speed: Double) -> String {
        var value = speed
        // Pad B to match the two-character units.
        var metric = " B"
        for nextMetric in ["KB", "MB", "GB", "TB"] {
            guard value >= 1024 else { break }
            value /= 1024
            metric = nextMetric
        }
        return String(format: "%6.2f %@/s", value, metric)
    }
}
