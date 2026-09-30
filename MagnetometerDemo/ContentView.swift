//
//  ContentView.swift
//  MagnetometerDemo
//
//  Shows the live magnetic field: the absolute value, each axis, a short
//  history chart, and a simple metal-detector readout.
//

import SwiftUI
import Charts

struct ContentView: View {
    /// The manager is @Observable, so any property the body reads
    /// (x, y, z, magnitude…) automatically refreshes the view when it changes.
    @State private var magnetometer = MagnetometerManager()

    /// Change from the baseline (in µT) that counts as "something magnetic nearby".
    private let detectionThreshold = 10.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Mode", selection: $magnetometer.mode) {
                        ForEach(MagnetometerMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if magnetometer.isAvailable {
                        magnitudeCard
                        axesCard
                        historyCard
                        detectorCard
                    } else {
                        ContentUnavailableView(
                            "No Magnetometer",
                            systemImage: "location.north.circle",
                            description: Text("This device (or the Simulator) doesn't provide magnetometer data. Run on a real iPhone.")
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Magnetometer")
        }
        // Start sensor updates when the screen appears and stop them when it
        // goes away, so the sensors aren't draining the battery in the background.
        .onAppear { magnetometer.start() }
        .onDisappear { magnetometer.stop() }
    }

    // MARK: - Absolute value

    private var magnitudeCard: some View {
        Card(title: "Absolute value  |B| = √(x² + y² + z²)") {
            HStack(alignment: .firstTextBaseline) {
                Text(magnetometer.magnitude, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("µT").font(.title2).foregroundStyle(.secondary)
                Spacer()
            }
            .monospacedDigit()

            HStack {
                Label("Accuracy", systemImage: "scope")
                Spacer()
                Text(magnetometer.accuracyDescription)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - x, y, z

    private var axesCard: some View {
        // Scale the bars to the magnitude. No single axis can be larger than
        // the whole vector, so the bars always fit.
        let scale = max(magnetometer.magnitude, 60)

        return Card(title: "Components (device axes, µT)") {
            AxisRow(label: "X", value: magnetometer.x, scale: scale, color: .red)
            AxisRow(label: "Y", value: magnetometer.y, scale: scale, color: .green)
            AxisRow(label: "Z", value: magnetometer.z, scale: scale, color: .blue)

            Text("Rotate the phone: x, y and z shift between each other, but |B| stays about the same.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - History chart

    private var historyCard: some View {
        Card(title: "|B| over the last 5 seconds") {
            Chart {
                ForEach(magnetometer.history) { sample in
                    LineMark(
                        x: .value("Time", sample.time),
                        y: .value("µT", sample.magnitude)
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Dashed line at the saved baseline, if any.
                if let baseline = magnetometer.baseline {
                    RuleMark(y: .value("Baseline", baseline))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.orange)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 160)
        }
    }

    // MARK: - Metal detector

    private var detectorCard: some View {
        let delta = magnetometer.deltaFromBaseline
        let detected = abs(delta ?? 0) > detectionThreshold

        return Card(title: "Metal detector") {
            if let delta {
                HStack {
                    Image(systemName: detected ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(detected ? .orange : .green)
                    Text(detected ? "Magnetic object nearby" : "Normal field")
                    Spacer()
                    Text(delta, format: .number.precision(.fractionLength(1)).sign(strategy: .always()))
                        .monospacedDigit()
                    Text("µT").foregroundStyle(.secondary)
                }
                .font(.headline)

                Button("Clear baseline", role: .destructive) { magnetometer.clearBaseline() }
            } else {
                Text("Hold the phone away from metal, then save a baseline. Bring it near a magnet or a steel object and watch |B| change.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Save baseline") { magnetometer.captureBaseline() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Subviews

/// One axis: a bar that grows right for positive values and left for negative ones.
private struct AxisRow: View {
    let label: String
    let value: Double
    let scale: Double
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 16)

            GeometryReader { geo in
                let half = geo.size.width / 2
                let length = min(abs(value) / scale, 1) * half

                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                    Rectangle()
                        .fill(color)
                        .frame(width: length)
                        .offset(x: value >= 0 ? half : half - length)
                    Rectangle()  // zero line
                        .fill(Color.secondary)
                        .frame(width: 1)
                        .offset(x: half)
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)

            Text(value, format: .number.precision(.fractionLength(1)))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
        }
    }
}

/// A simple rounded container with a caption title.
private struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
