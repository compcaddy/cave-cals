import SwiftUI
import PDFKit
import UIKit

struct ProgressPrintDocument {
    let weeks: [ProgressWeek]
    let dates: ProgressCalendar
    let unit: WeightUnit
    var dailyGoal: Double? = nil
    var priorWeek: ProgressWeek? = nil
    var isInProgress = false

    private func fullWeekLabel(_ interval: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.calendar = dates.calendar; formatter.timeZone = dates.calendar.timeZone
        formatter.dateFormat = "EEEE, MMMM"
        let ordinal = NumberFormatter(); ordinal.numberStyle = .ordinal
        func day(_ date: Date) -> String {
            let n = dates.calendar.component(.day, from: date)
            return formatter.string(from: date) + " " + (ordinal.string(from: NSNumber(value: n)) ?? String(n))
        }
        return day(interval.start) + " – " + day(dates.calendar.date(byAdding: .day, value: -1, to: interval.end)!)
    }

    @MainActor func pdf() -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            UIColor.white.setFill(); context.cgContext.fill(bounds)
            let ink = UIColor(white: 0.12, alpha: 1)
            let muted = UIColor(white: 0.4, alpha: 1)
            let orange = UIColor(red: 0.66, green: 0.25, blue: 0.07, alpha: 1)
            let tan = UIColor(red: 0.98, green: 0.94, blue: 0.88, alpha: 1)
            func text(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 11, bold: Bool = false, color: UIColor? = nil) {
                let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
                (text as NSString).draw(in: CGRect(x: x, y: y, width: width, height: 45), withAttributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
                    .foregroundColor: color ?? ink, .paragraphStyle: style
                ])
            }
            func line(_ y: CGFloat, heavy: Bool = false) {
                context.cgContext.setStrokeColor(UIColor(white: heavy ? 0.4 : 0.85, alpha: 1).cgColor)
                context.cgContext.setLineWidth(heavy ? 1.3 : 0.5)
                context.cgContext.move(to: CGPoint(x: 36, y: y))
                context.cgContext.addLine(to: CGPoint(x: 576, y: y)); context.cgContext.strokePath()
            }
            func number(_ value: Double?, weight: Bool) -> String {
                value.map { weight ? unit.display($0).formatted(.number.precision(.fractionLength(1))) : $0.calorieText } ?? "—"
            }
            guard let latest = weeks.last else { return }
            let previous = weeks.dropLast().last
            text("CAVE CALS", x: 36, y: 28, width: 540, size: 11, bold: true, color: orange)
            text("Weekly Recap", x: 36, y: 49, width: 540, size: 30, bold: true)
            text(fullWeekLabel(latest.interval), x: 36, y: 92, width: 540, size: 13, color: muted)
            if isInProgress { text("In progress", x: 36, y: 112, width: 540, size: 10, color: orange) }
            for (i, isWeight) in [true, false].enumerated() {
                let x: CGFloat = i == 0 ? 36 : 316
                let stats = isWeight ? latest.weight : latest.calories
                text(isWeight ? "AVERAGE WEIGHT" : "AVERAGE DAILY CALORIES", x: x, y: 132, width: 260, size: 10, bold: true, color: muted)
                text(number(stats.average, weight: isWeight) + (isWeight ? " " + unit.rawValue : " cals"), x: x, y: 150, width: 260, size: 31, bold: true)
                tan.setFill(); UIBezierPath(roundedRect: CGRect(x: x, y: 197, width: 260, height: 36), cornerRadius: 7).fill()
                let comparison = isWeight
                    ? ProgressFormat.change(previous.flatMap { stats.change(from: $0.weight) }, unit: unit)
                    : ProgressFormat.goalChange(average: stats.average, goal: dailyGoal)
                text(comparison, x: x + 10, y: 205, width: 240, size: 15, bold: true, color: orange)
                text("Min \(number(stats.min, weight: isWeight))  /  Max \(number(stats.max, weight: isWeight))", x: x, y: 247, width: 260)
                text("\(stats.count)/7 \(isWeight ? "weigh-ins" : "completed calorie days")", x: x, y: 266, width: 260, size: 10, color: muted)
                if isWeight, let previous {
                    text("Compared with " + dates.label(previous.interval), x: x, y: 286, width: 260, size: 9, color: muted)
                } else if !isWeight, let dailyGoal, dailyGoal > 0 {
                    text("Daily goal: " + dailyGoal.calorieText + " cals", x: x, y: 286, width: 260, size: 10, color: muted)
                }
            }
            line(318, heavy: true)
            text("Six-Week Trends", x: 36, y: 339, width: 540, size: 24, bold: true)
            text(dates.label(DateInterval(start: weeks.first!.interval.start, end: latest.interval.end)), x: 36, y: 373, width: 540, size: 11, color: muted)
            text("Average weight (\(unit.rawValue))", x: 36, y: 405, width: 248)
            text("Average daily calories", x: 328, y: 405, width: 248)
            trend(values: weeks.map { $0.weight.average.map(unit.display) }, rect: CGRect(x: 36, y: 438, width: 248, height: 80), bars: false, context: context.cgContext, color: orange)
            trend(values: weeks.map { $0.calories.average }, rect: CGRect(x: 328, y: 438, width: 248, height: 80), bars: true, context: context.cgContext, color: orange)
            let step = 248.0 / CGFloat(max(weeks.count, 1))
            for i in weeks.indices {
                let label = weeks[i].interval.start.formatted(.dateTime.month(.abbreviated).day())
                text(label, x: 36 + CGFloat(i) * step, y: 530, width: step, size: 8, color: muted)
                text(label, x: 328 + CGFloat(i) * step, y: 530, width: step, size: 8, color: muted)
            }
            line(552)
            let xs: [CGFloat] = [36, 146, 257, 371, 480]
            let widths: [CGFloat] = [104, 105, 108, 103, 96]
            let headers = ["Week starting", "Avg cals · change", "Calorie min–max", "Avg \(unit.rawValue) · change", "Weight min–max"]
            for i in headers.indices { text(headers[i], x: xs[i], y: 567, width: widths[i], size: 9, bold: true, color: muted) }
            for (i, week) in weeks.enumerated() {
                let y = CGFloat(591 + i * 26)
                let isLatest = i == weeks.count - 1
                if isLatest {
                    tan.setFill(); context.cgContext.fill(CGRect(x: 30, y: y - 4, width: 552, height: 26))
                }
                let fields = [week.interval.start.formatted(.dateTime.month(.abbreviated).day()),
                    number(week.calories.average, weight: false),
                    number(week.calories.min, weight: false) + "–" + number(week.calories.max, weight: false),
                    number(week.weight.average, weight: true),
                    number(week.weight.min, weight: true) + "–" + number(week.weight.max, weight: true)]
                for column in fields.indices {
                    text(fields[column], x: xs[column], y: y, width: widths[column], size: 11, bold: isLatest)
                }
                let prior = i > 0 ? weeks[i - 1] : priorWeek
                for (column, isWeight) in [(1, false), (3, true)] {
                    let stats = isWeight ? week.weight : week.calories
                    let before = isWeight ? prior?.weight : prior?.calories
                    let delta = ProgressFormat.signedChange(before.flatMap { stats.change(from: $0) }, unit: isWeight ? unit : nil)
                    let valueWidth = (fields[column] as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: isLatest ? .semibold : .regular)]).width
                    text(delta, x: xs[column] + valueWidth + 7, y: y + 1, width: widths[column] - valueWidth - 7, size: 9, color: muted)
                }
                text("\(week.calories.count)/7 food · \(week.weight.count)/7 weight", x: xs[0], y: y + 13, width: widths[0], size: 7, color: muted)
            }
        }
    }

    @MainActor private func trend(values: [Double?], rect: CGRect, bars: Bool, context: CGContext, color: UIColor) {
        let known = values.compactMap { $0 }
        guard let highest = known.max(), let lowest = known.min() else {
            ("No recorded data" as NSString).draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.gray]); return
        }
        let low = bars ? 0 : lowest - max(0.3, (highest - lowest) * 0.3)
        let high = max(low + 1, highest + (bars ? highest * 0.25 : max(0.3, (highest - lowest) * 0.3)))
        context.setStrokeColor(UIColor.lightGray.cgColor); context.setLineWidth(0.5)
        context.move(to: CGPoint(x: rect.minX, y: rect.maxY)); context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); context.strokePath()
        let step = rect.width / CGFloat(max(values.count, 1))
        var previous: CGPoint?
        for (i, value) in values.enumerated() {
            guard let value else { previous = nil; continue }
            let x = rect.minX + (CGFloat(i) + 0.5) * step
            let y = rect.maxY - CGFloat((value - low) / (high - low)) * rect.height
            context.setFillColor(color.cgColor); context.setStrokeColor(color.cgColor); context.setLineWidth(2)
            if bars { context.fill(CGRect(x: x - step * 0.3, y: y, width: step * 0.6, height: rect.maxY - y)) }
            else {
                if let previous { context.move(to: previous); context.addLine(to: CGPoint(x: x, y: y)); context.strokePath() }
                context.fillEllipse(in: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
            }
            let label = value.formatted(.number.precision(.fractionLength(bars ? 0 : 1)))
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            (label as NSString).draw(in: CGRect(x: x - step / 2, y: y - 15, width: step, height: 15), withAttributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.darkGray, .paragraphStyle: paragraph])
            previous = CGPoint(x: x, y: y)
        }
    }
}

struct ProgressPrintPreview: View {
    let document: ProgressPrintDocument
    @Environment(\.dismiss) private var dismiss
    @State private var pdfData: Data?
    @State private var url: URL?
    @State private var printing = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Group {
                if let pdfData { ProgressPDFView(data: pdfData) }
                else { SwiftUI.ProgressView() }
            }
            .navigationTitle("Weekly Recap").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.hapticButtonStyle(.automatic) }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let url { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share report PDF") }
                    Button("Print") { printing = true }.hapticButtonStyle(.automatic).disabled(pdfData == nil).accessibilityIdentifier("sendProgressToPrinter")
                }
            }
            .background { if let pdfData { ProgressPrintPresenter(data: pdfData, requested: $printing, error: $error).frame(width: 1, height: 1) } }
            .alert("Couldn’t print report", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { Haptics.play(.tap); error = nil }.hapticFeel(.none)
            } message: { Text(error ?? "") }
            .task {
                guard pdfData == nil else { return }
                let data = document.pdf(); pdfData = data
                let output = FileManager.default.temporaryDirectory.appendingPathComponent("CaveCals-progress-\(UUID().uuidString).pdf")
                do { try data.write(to: output, options: [.atomic, .completeFileProtection]); url = output }
                catch { self.error = error.localizedDescription }
            }
            .onDisappear { if let url { try? FileManager.default.removeItem(at: url) } }
        }
    }
}

private struct ProgressPDFView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data); return view
    }
    func updateUIView(_ view: PDFView, context: Context) { }
}

private struct ProgressPrintPresenter: UIViewControllerRepresentable {
    let data: Data
    @Binding var requested: Bool
    @Binding var error: String?
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard requested else { return }
        DispatchQueue.main.async {
            requested = false
            let printer = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil); info.jobName = "Cave Cals Weekly Recap"; info.outputType = .general
            printer.printInfo = info; printer.printingItem = data
            guard UIPrintInteractionController.isPrintingAvailable else {
                error = "Printing is unavailable. You can share or save the PDF instead."; return
            }
            let presented = printer.present(from: controller.view.bounds, in: controller.view, animated: true) { _, _, failure in
                if let failure { error = failure.localizedDescription }
            }
            if !presented { error = "The print options couldn’t open. Try again or share the PDF." }
        }
    }
}
