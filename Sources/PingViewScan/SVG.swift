import Foundation

/// Minimal SVG line-chart generator used by the HTML report. Produces inline SVG
/// (no XML prolog) so it can be embedded directly in a web page.
enum SVG {

    struct Series {
        let name: String
        let color: String
        /// Ordered (time, value) points. `value` is already in the chart's units.
        let points: [(Date, Double)]
    }

    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Round a maximum value up to a "nice" 1/2/5 x 10^n number.
    static func niceMax(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let exponent = floor(log10(value))
        let base = pow(10.0, exponent)
        let normalized = value / base
        let nice: Double
        switch normalized {
        case ..<1.0001: nice = 1
        case ..<2.0001: nice = 2
        case ..<5.0001: nice = 5
        default: nice = 10
        }
        return nice * base
    }

    static func lineChart(width: Double,
                          height: Double,
                          title: String,
                          series: [Series],
                          yMin: Double,
                          yMax: Double,
                          yLabel: String,
                          start: Date,
                          end: Date,
                          lostMarkers: [Date] = []) -> String {

        let marginLeft = 72.0
        let marginRight = 210.0
        let marginTop = 46.0
        let marginBottom = 50.0
        let plotWidth = max(10, width - marginLeft - marginRight)
        let plotHeight = max(10, height - marginTop - marginBottom)
        let timeSpan = max(0.001, end.timeIntervalSince(start))
        let valueSpan = max(0.0001, yMax - yMin)

        func xFor(_ date: Date) -> Double {
            let ratio = date.timeIntervalSince(start) / timeSpan
            return marginLeft + min(max(ratio, 0), 1) * plotWidth
        }
        func yFor(_ value: Double) -> Double {
            let ratio = (value - yMin) / valueSpan
            return marginTop + (1 - min(max(ratio, 0), 1)) * plotHeight
        }

        var svg = ""
        svg += "<svg viewBox=\"0 0 \(fmt(width)) \(fmt(height))\" width=\"100%\" "
        svg += "preserveAspectRatio=\"xMidYMid meet\" role=\"img\" "
        svg += "font-family=\"-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif\">"
        svg += "<rect x=\"0\" y=\"0\" width=\"\(fmt(width))\" height=\"\(fmt(height))\" fill=\"#ffffff\"/>"
        svg += "<text x=\"\(fmt(marginLeft))\" y=\"26\" font-size=\"16\" font-weight=\"600\" fill=\"#111827\">\(escape(title))</text>"

        // Horizontal grid + y labels
        let ySteps = 5
        for step in 0...ySteps {
            let value = yMin + valueSpan * Double(step) / Double(ySteps)
            let y = yFor(value)
            svg += "<line x1=\"\(fmt(marginLeft))\" y1=\"\(fmt(y))\" x2=\"\(fmt(marginLeft + plotWidth))\" y2=\"\(fmt(y))\" stroke=\"#eef0f3\"/>"
            svg += "<text x=\"\(fmt(marginLeft - 10))\" y=\"\(fmt(y + 4))\" font-size=\"11\" fill=\"#6b7280\" text-anchor=\"end\">\(tickLabel(value, span: valueSpan))</text>"
        }

        // Vertical grid + time labels
        let xSteps = 6
        for step in 0...xSteps {
            let date = start.addingTimeInterval(timeSpan * Double(step) / Double(xSteps))
            let x = xFor(date)
            svg += "<line x1=\"\(fmt(x))\" y1=\"\(fmt(marginTop))\" x2=\"\(fmt(x))\" y2=\"\(fmt(marginTop + plotHeight))\" stroke=\"#f4f5f7\"/>"
            svg += "<text x=\"\(fmt(x))\" y=\"\(fmt(marginTop + plotHeight + 18))\" font-size=\"11\" fill=\"#6b7280\" text-anchor=\"middle\">\(timeLabel(date))</text>"
        }

        // Axes
        svg += "<line x1=\"\(fmt(marginLeft))\" y1=\"\(fmt(marginTop))\" x2=\"\(fmt(marginLeft))\" y2=\"\(fmt(marginTop + plotHeight))\" stroke=\"#9ca3af\"/>"
        svg += "<line x1=\"\(fmt(marginLeft))\" y1=\"\(fmt(marginTop + plotHeight))\" x2=\"\(fmt(marginLeft + plotWidth))\" y2=\"\(fmt(marginTop + plotHeight))\" stroke=\"#9ca3af\"/>"
        svg += "<text transform=\"translate(18 \(fmt(marginTop + plotHeight / 2))) rotate(-90)\" font-size=\"12\" fill=\"#374151\" text-anchor=\"middle\">\(escape(yLabel))</text>"

        // Lost-packet ticks along the baseline
        for date in lostMarkers {
            let x = xFor(date)
            svg += "<line x1=\"\(fmt(x))\" y1=\"\(fmt(marginTop + plotHeight))\" x2=\"\(fmt(x))\" y2=\"\(fmt(marginTop + plotHeight - 7))\" stroke=\"#dc2626\" stroke-width=\"1.4\" opacity=\"0.8\"/>"
        }

        // Series
        for serie in series {
            guard !serie.points.isEmpty else { continue }
            if serie.points.count == 1 {
                let point = serie.points[0]
                svg += "<circle cx=\"\(fmt(xFor(point.0)))\" cy=\"\(fmt(yFor(point.1)))\" r=\"3\" fill=\"\(serie.color)\"/>"
                continue
            }
            var path = ""
            for (index, point) in serie.points.enumerated() {
                path += index == 0 ? "M" : "L"
                path += "\(fmt(xFor(point.0))) \(fmt(yFor(point.1))) "
            }
            svg += "<path d=\"\(path.trimmingCharacters(in: .whitespaces))\" fill=\"none\" stroke=\"\(serie.color)\" stroke-width=\"1.6\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>"
        }

        // Legend
        var legendY = marginTop + 2
        for serie in series {
            let swatchX = marginLeft + plotWidth + 18
            svg += "<rect x=\"\(fmt(swatchX))\" y=\"\(fmt(legendY - 9))\" width=\"12\" height=\"12\" rx=\"3\" fill=\"\(serie.color)\"/>"
            svg += "<text x=\"\(fmt(swatchX + 18))\" y=\"\(fmt(legendY))\" font-size=\"12\" fill=\"#374151\">\(escape(truncate(serie.name, 22)))</text>"
            legendY += 18
        }

        svg += "</svg>"
        return svg
    }

    /// Simple vertical bar chart, e.g. latency per host or port popularity.
    static func barChart(width: Double,
                         height: Double,
                         title: String,
                         bars: [(label: String, value: Double, color: String)],
                         yLabel: String,
                         rotateLabels: Bool = false,
                         integerValues: Bool = false,
                         valueSuffix: String = "") -> String {

        let marginLeft = 68.0
        let marginRight = 24.0
        let marginTop = 46.0
        let marginBottom = rotateLabels ? 132.0 : 52.0
        let plotWidth = max(10, width - marginLeft - marginRight)
        let plotHeight = max(10, height - marginTop - marginBottom)
        let maxValue = niceMax(max(bars.map { $0.value }.max() ?? 1, 0.0001))

        func yFor(_ value: Double) -> Double {
            marginTop + (1 - min(max(value / maxValue, 0), 1)) * plotHeight
        }

        func label(_ value: Double) -> String {
            integerValues ? String(format: "%.0f", value) : tickLabel(value, span: maxValue)
        }

        var svg = ""
        svg += "<svg viewBox=\"0 0 \(fmt(width)) \(fmt(height))\" width=\"100%\" "
        svg += "preserveAspectRatio=\"xMidYMid meet\" role=\"img\" "
        svg += "font-family=\"-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif\">"
        svg += "<rect x=\"0\" y=\"0\" width=\"\(fmt(width))\" height=\"\(fmt(height))\" fill=\"#ffffff\"/>"
        svg += "<text x=\"\(fmt(marginLeft))\" y=\"26\" font-size=\"16\" font-weight=\"600\" fill=\"#111827\">\(escape(title))</text>"

        let ySteps = 5
        for step in 0...ySteps {
            let value = maxValue * Double(step) / Double(ySteps)
            let y = yFor(value)
            svg += "<line x1=\"\(fmt(marginLeft))\" y1=\"\(fmt(y))\" x2=\"\(fmt(marginLeft + plotWidth))\" y2=\"\(fmt(y))\" stroke=\"#eef0f3\"/>"
            svg += "<text x=\"\(fmt(marginLeft - 10))\" y=\"\(fmt(y + 4))\" font-size=\"11\" fill=\"#6b7280\" text-anchor=\"end\">\(label(value))</text>"
        }
        svg += "<line x1=\"\(fmt(marginLeft))\" y1=\"\(fmt(marginTop))\" x2=\"\(fmt(marginLeft))\" y2=\"\(fmt(marginTop + plotHeight))\" stroke=\"#9ca3af\"/>"
        svg += "<line x1=\"\(fmt(marginLeft))\" y1=\"\(fmt(marginTop + plotHeight))\" x2=\"\(fmt(marginLeft + plotWidth))\" y2=\"\(fmt(marginTop + plotHeight))\" stroke=\"#9ca3af\"/>"
        svg += "<text transform=\"translate(18 \(fmt(marginTop + plotHeight / 2))) rotate(-90)\" font-size=\"12\" fill=\"#374151\" text-anchor=\"middle\">\(escape(yLabel))</text>"

        if !bars.isEmpty {
            let slot = plotWidth / Double(bars.count)
            let barWidth = min(slot * 0.72, 64)
            for (index, bar) in bars.enumerated() {
                let centerX = marginLeft + slot * (Double(index) + 0.5)
                let top = yFor(bar.value)
                let barHeight = marginTop + plotHeight - top
                svg += "<rect x=\"\(fmt(centerX - barWidth / 2))\" y=\"\(fmt(top))\" width=\"\(fmt(barWidth))\" height=\"\(fmt(max(0, barHeight)))\" rx=\"2\" fill=\"\(bar.color)\"/>"
                if bar.value > 0 {
                    svg += "<text x=\"\(fmt(centerX))\" y=\"\(fmt(top - 4))\" text-anchor=\"middle\" font-size=\"10\" fill=\"#6b7280\">\(label(bar.value))\(escape(valueSuffix))</text>"
                }
                if rotateLabels {
                    svg += "<text transform=\"translate(\(fmt(centerX)) \(fmt(marginTop + plotHeight + 6))) rotate(-60)\" text-anchor=\"end\" font-size=\"10\" fill=\"#6b7280\">\(escape(truncate(bar.label, 20)))</text>"
                } else {
                    svg += "<text x=\"\(fmt(centerX))\" y=\"\(fmt(marginTop + plotHeight + 16))\" text-anchor=\"middle\" font-size=\"10\" fill=\"#6b7280\">\(escape(truncate(bar.label, 18)))</text>"
                }
            }
        }

        svg += "</svg>"
        return svg
    }

    // MARK: - Helpers

    private static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func tickLabel(_ value: Double, span: Double) -> String {
        if span >= 20 { return String(format: "%.0f", value) }
        if span >= 5 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func timeLabel(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    private static func truncate(_ string: String, _ maxLength: Int) -> String {
        string.count > maxLength ? String(string.prefix(maxLength - 1)) + "\u{2026}" : string
    }
}
