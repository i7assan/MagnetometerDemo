//
//  MagnetometerManager.swift
//  MagnetometerDemo
//
//  Wraps Core Motion and exposes the magnetic field (x, y, z) and its
//  absolute value (magnitude) to SwiftUI.
//
//  All values are in microtesla (µT).
//  For reference, Earth's field is roughly 25–65 µT depending on where you are
//  (around 40 µT in Saudi Arabia).
//

import CoreMotion
import Observation

/// Which Core Motion API we read the magnetic field from.
enum MagnetometerMode: String, CaseIterable, Identifiable {
    /// `CMDeviceMotion.magneticField`: Core Motion has removed the device's own
    /// magnetic bias (hard-iron offset). This is usually what you want.
    case calibrated = "Calibrated"

    /// `CMMagnetometerData.magneticField`: straight from the sensor, including
    /// the bias from the phone's own electronics. Magnitude can read in the
    /// hundreds of µT even far away from any magnet.
    case raw = "Raw"

    var id: Self { self }
}

/// One magnitude reading, kept so the UI can draw a history chart.
struct MagneticSample: Identifiable {
    let id = UUID()
    let time: Date
    let magnitude: Double
}

@MainActor
@Observable
final class MagnetometerManager {

    // MARK: - Configuration

    /// How often Core Motion delivers samples. 30 Hz is smooth for UI and
    /// light on battery. The hardware can go up to ~100 Hz.
    private let updateInterval: TimeInterval = 1.0 / 30.0

    /// Keep about 5 seconds of history for the chart (30 Hz × 5 s).
    private let maxSamples = 150

    /// Use ONE CMMotionManager per app. Apple recommends against creating
    /// several, since each one competes for the same sensor hardware.
    private let motionManager = CMMotionManager()

    // MARK: - Published state (SwiftUI observes these)

    /// Field components along the DEVICE's axes, in µT:
    ///  • x: points to the right edge of the screen
    ///  • y: points to the top of the screen
    ///  • z: points out of the screen, toward you
    /// These change as you rotate the phone, because the axes rotate with it.
    private(set) var x = 0.0
    private(set) var y = 0.0
    private(set) var z = 0.0

    /// Calibration quality. Only reported in `.calibrated` mode; nil in `.raw`.
    private(set) var accuracy: CMMagneticFieldCalibrationAccuracy?

    private(set) var history: [MagneticSample] = []
    private(set) var isRunning = false

    /// Magnitude captured by the user to compare against (metal detector mode).
    private(set) var baseline: Double?

    /// Switching mode restarts updates using the other API.
    var mode: MagnetometerMode = .calibrated {
        didSet {
            guard mode != oldValue, isRunning else { return }
            stop()
            start()
        }
    }

    // MARK: - Derived values

    /// The ABSOLUTE VALUE of the field: the length of the (x, y, z) vector.
    ///
    ///     |B| = √(x² + y² + z²)
    ///
    /// Unlike the individual axes, this does NOT change when you rotate the
    /// phone, since rotating a vector doesn't change its length. That makes it
    /// the useful number for detecting magnets and ferrous metal.
    var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// How far the current magnitude is from the saved baseline.
    var deltaFromBaseline: Double? {
        baseline.map { magnitude - $0 }
    }

    /// Whether the hardware and API needed for the current mode exist.
    /// This is false in the Simulator, which has no magnetometer.
    var isAvailable: Bool {
        switch mode {
        case .calibrated:
            // Calibrated data comes through device motion, and only when we use
            // a reference frame that involves the magnetometer.
            return motionManager.isDeviceMotionAvailable
                && CMMotionManager.availableAttitudeReferenceFrames()
                    .contains(.xArbitraryCorrectedZVertical)
        case .raw:
            return motionManager.isMagnetometerAvailable
        }
    }

    var accuracyDescription: String {
        guard let accuracy else { return "n/a (raw)" }
        return switch accuracy {
        case .uncalibrated: "Uncalibrated"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        @unknown default: "Unknown"
        }
    }

    // MARK: - Init

    init() {
        // When calibration is poor, let iOS show its "move your iPhone in a
        // figure-8" prompt. This only affects device-motion (calibrated) updates.
        motionManager.showsDeviceMovementDisplay = true
    }

    // MARK: - Start / stop

    func start() {
        guard !isRunning, isAvailable else { return }
        history.removeAll()
        accuracy = nil

        switch mode {
        case .calibrated: startCalibratedUpdates()
        case .raw: startRawUpdates()
        }
        isRunning = true
    }

    /// Always stop updates when you're done. The sensors keep draining the
    /// battery for as long as updates are running.
    func stop() {
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopMagnetometerUpdates()
        isRunning = false
    }

    // MARK: - Option 1: calibrated field (recommended)

    private func startCalibratedUpdates() {
        motionManager.deviceMotionUpdateInterval = updateInterval

        // Reference frame matters: `magneticField` is only filled in when the
        // frame uses the magnetometer. `.xArbitraryZVertical` (the default)
        // would leave the field at zero with `.uncalibrated` accuracy.
        //
        // We deliver to `.main` because every sample updates the UI. If you
        // do heavy processing per sample, pass your own OperationQueue and hop
        // to the main actor only to publish results.
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryCorrectedZVertical,
            to: .main
        ) { [weak self] motion, error in
            guard let motion, error == nil else { return }

            // CMCalibratedMagneticField = the bias-corrected vector + an accuracy.
            let field = motion.magneticField
            let (bx, by, bz) = (field.field.x, field.field.y, field.field.z)
            let accuracy = field.accuracy

            // We asked for delivery on the main queue, so we're already on the
            // main actor. This just tells the compiler.
            MainActor.assumeIsolated {
                self?.accuracy = accuracy
                self?.record(x: bx, y: by, z: bz)
            }
        }
    }

    // MARK: - Option 2: raw sensor readings

    private func startRawUpdates() {
        motionManager.magnetometerUpdateInterval = updateInterval

        motionManager.startMagnetometerUpdates(to: .main) { [weak self] data, error in
            guard let data, error == nil else { return }

            // CMMagneticField = the raw (x, y, z) straight from the sensor,
            // including the device's hard-iron bias. No accuracy is reported.
            let field = data.magneticField
            let (bx, by, bz) = (field.x, field.y, field.z)

            MainActor.assumeIsolated {
                self?.record(x: bx, y: by, z: bz)
            }
        }
    }

    // MARK: - Baseline (metal detector)

    /// Save the current magnitude, so later readings can be compared to it.
    func captureBaseline() {
        baseline = magnitude
    }

    func clearBaseline() {
        baseline = nil
    }

    // MARK: - Helpers

    /// Stores the newest reading and appends its magnitude to the chart history.
    private func record(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z

        history.append(MagneticSample(time: .now, magnitude: magnitude))
        if history.count > maxSamples {
            history.removeFirst(history.count - maxSamples)
        }
    }
}
