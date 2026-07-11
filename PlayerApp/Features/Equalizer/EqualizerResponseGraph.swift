import SwiftUI

struct EqualizerResponseGraph: View {
    var response: EQFrequencyResponse
    var bandResponses: [UUID: EQFrequencyResponse] = [:]
    var bands: [PEQBand]
    var spectrum: SpectrumSnapshot? = nil
    var selectedBandID: UUID?
    var frequencyRange: ClosedRange<Double> = 20...20_000
    var gainRange: ClosedRange<Double> = -24...24
    var onSelectBand: (UUID) -> Void
    var onDragSelectedBand: (Double, Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let geometry = EqualizerGraphGeometry(
                size: proxy.size,
                frequencyRange: frequencyRange,
                gainRange: gainRange
            )
            ZStack {
                Canvas { context, _ in
                    drawGrid(context: context, geometry: geometry)
                    drawSpectrum(context: context, geometry: geometry)
                    drawBandResponses(context: context, geometry: geometry)
                    drawResponse(context: context, geometry: geometry)
                    drawBands(context: context, geometry: geometry)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if selectedBandID == nil,
                       let nearest = nearestBand(to: value.startLocation, geometry: geometry) {
                        onSelectBand(nearest.id)
                    }
                    onDragSelectedBand(
                        geometry.frequency(forX: value.location.x),
                        geometry.gainDB(forY: value.location.y)
                    )
                })
            }
        }
        .frame(minHeight: 190)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAdjustableAction { direction in
            guard let selected = bands.first(where: { $0.id == selectedBandID }) else { return }
            let delta = direction == .increment ? 0.5 : -0.5
            onDragSelectedBand(selected.frequencyHz, selected.gainDB + delta)
        }
    }

    private func nearestBand(
        to point: CGPoint,
        geometry: EqualizerGraphGeometry
    ) -> PEQBand? {
        bands.min { lhs, rhs in
            let lhsPoint = CGPoint(
                x: geometry.x(forFrequency: lhs.frequencyHz),
                y: geometry.y(forGainDB: lhs.gainDB)
            )
            let rhsPoint = CGPoint(
                x: geometry.x(forFrequency: rhs.frequencyHz),
                y: geometry.y(forGainDB: rhs.gainDB)
            )
            return hypot(lhsPoint.x - point.x, lhsPoint.y - point.y) < hypot(rhsPoint.x - point.x, rhsPoint.y - point.y)
        }
    }

    private func drawGrid(context: GraphicsContext, geometry: EqualizerGraphGeometry) {
        var path = Path()
        for frequency in [20.0, 50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000] {
            guard geometry.frequencyRange.contains(frequency) else { continue }
            let x = geometry.x(forFrequency: frequency)
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
        }
        let gainStep = geometry.gainRange.upperBound - geometry.gainRange.lowerBound > 60
            ? 12.0
            : 6.0
        let firstGain = ceil(geometry.gainRange.lowerBound / gainStep) * gainStep
        for gain in stride(
            from: firstGain,
            through: geometry.gainRange.upperBound,
            by: gainStep
        ) {
            let y = geometry.y(forGainDB: gain)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
        }
        context.stroke(path, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)
    }

    private func drawResponse(context: GraphicsContext, geometry: EqualizerGraphGeometry) {
        guard let first = response.points.first else { return }
        var path = Path()
        path.move(to: CGPoint(
            x: geometry.x(forFrequency: first.frequencyHz),
            y: geometry.y(forGainDB: first.gainDB)
        ))
        for point in response.points.dropFirst() {
            path.addLine(to: CGPoint(
                x: geometry.x(forFrequency: point.frequencyHz),
                y: geometry.y(forGainDB: point.gainDB)
            ))
        }
        context.stroke(path, with: .color(.accentColor), lineWidth: 2)
    }

    private func drawBandResponses(
        context: GraphicsContext,
        geometry: EqualizerGraphGeometry
    ) {
        for (bandID, response) in bandResponses {
            guard let first = response.points.first else { continue }
            var path = Path()
            path.move(to: CGPoint(
                x: geometry.x(forFrequency: first.frequencyHz),
                y: geometry.y(forGainDB: first.gainDB)
            ))
            for point in response.points.dropFirst() {
                path.addLine(to: CGPoint(
                    x: geometry.x(forFrequency: point.frequencyHz),
                    y: geometry.y(forGainDB: point.gainDB)
                ))
            }
            let isSelected = bandID == selectedBandID
            context.stroke(
                path,
                with: .color(isSelected ? .primary.opacity(0.75) : .secondary.opacity(0.35)),
                lineWidth: isSelected ? 1.25 : 0.75
            )
        }
    }

    private func drawSpectrum(context: GraphicsContext, geometry: EqualizerGraphGeometry) {
        guard let bins = spectrum?.bins, let first = bins.first else { return }
        func y(_ decibels: Double) -> CGFloat {
            let normalized = min(max((decibels + 100) / 100, 0), 1)
            return geometry.size.height * CGFloat(1 - normalized)
        }
        var path = Path()
        path.move(to: CGPoint(x: geometry.x(forFrequency: first.frequencyHz), y: geometry.size.height))
        for bin in bins {
            path.addLine(to: CGPoint(
                x: geometry.x(forFrequency: bin.frequencyHz),
                y: y(bin.magnitudeDB)
            ))
        }
        path.addLine(to: CGPoint(
            x: geometry.x(forFrequency: bins.last?.frequencyHz ?? first.frequencyHz),
            y: geometry.size.height
        ))
        path.closeSubpath()
        context.fill(path, with: .color(.secondary.opacity(0.18)))
    }

    private func drawBands(context: GraphicsContext, geometry: EqualizerGraphGeometry) {
        for band in bands where band.isEnabled {
            let point = CGPoint(
                x: geometry.x(forFrequency: band.frequencyHz),
                y: geometry.y(forGainDB: band.gainDB)
            )
            let selected = band.id == selectedBandID
            let rect = CGRect(
                x: point.x - (selected ? 7 : 5),
                y: point.y - (selected ? 7 : 5),
                width: selected ? 14 : 10,
                height: selected ? 14 : 10
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(selected ? .accentColor : .secondary)
            )
        }
    }

    private var accessibilityDescription: String {
        guard let band = bands.first(where: { $0.id == selectedBandID }) else {
            return String(localized: "Equalizer response graph. No band selected.")
        }
        return LocalizedFormat.string(
            "Equalizer response graph. Selected band at %lld hertz, %@ decibels. Swipe up or down to adjust gain.",
            Int64(band.frequencyHz.rounded()),
            band.gainDB.formatted(.number.precision(.fractionLength(1)))
        )
    }
}
