import Foundation
import UIKit
import Vision

enum ReceiptOCR {
    struct Suggestion: Equatable {
        var title: String?
        var amount: Decimal?
        var date: Date?

        var hasAnyValue: Bool {
            title != nil || amount != nil || date != nil
        }
    }

    enum Failure: Error, Equatable {
        case cancelled
        case unreadable
        case visionFailed
    }

    static func recognize(_ image: UIImage) async throws -> Suggestion {
        let prepared = image.preparedForOCR()
        guard let cgImage = prepared.cgImage else {
            throw Failure.unreadable
        }

        let observations: [VNRecognizedTextObservation] = try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            func resumeOnce(_ result: Result<[VNRecognizedTextObservation], Error>) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    resumeOnce(.failure(error))
                    return
                }
                let found = (request.results as? [VNRecognizedTextObservation]) ?? []
                resumeOnce(.success(found))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = true

            let orientation = CGImagePropertyOrientation(prepared.imageOrientation)
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    resumeOnce(.failure(error))
                }
            }
        }

        return parse(observations)
    }

    static func parse(_ observations: [VNRecognizedTextObservation]) -> Suggestion {
        let lines: [Line] = observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let box = observation.boundingBox
            return Line(
                text: trimmed,
                top: 1 - CGFloat(box.maxY),
                bottom: 1 - CGFloat(box.minY),
                midYFromTop: 1 - CGFloat(box.midY)
            )
        }
        .sorted { $0.top < $1.top }

        return Suggestion(
            title: inferTitle(from: lines),
            amount: inferAmount(from: lines),
            date: inferDate(from: lines)
        )
    }
}

private struct Line {
    let text: String
    let top: CGFloat
    let bottom: CGFloat
    let midYFromTop: CGFloat

    var normalized: String {
        text.lowercased()
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
    }
}

private extension ReceiptOCR {
    static let totalKeywords = [
        "zu zahlen", "zahlbetrag", "gesamtsumme", "gesamtbetrag", "endsumme",
        "summe eur", "summe euro", "summe €", "summe",
        "total", "gesamt", "kartenumsatz"
    ]

    static let ignoreAmountKeywords = [
        "mwst", "ust-id", "ust id", "ust.", "netto", "steuer",
        "rueckgeld", "ruckgeld", "wechselgeld", "gegeben", "gabe",
        "stueck", "anzahl", "menge", "pfand"
    ]

    static func inferAmount(from lines: [Line]) -> Decimal? {
        let labeled = lines.compactMap { line -> Decimal? in
            guard containsAny(totalKeywords, in: line.normalized) else { return nil }
            guard !containsAny(ignoreAmountKeywords, in: line.normalized) else { return nil }
            if let amount = amounts(in: line.text).last {
                return amount
            }
            return nil
        }

        if let labeledBest = labeled.max() {
            return labeledBest
        }

        for (index, line) in lines.enumerated() where containsAny(totalKeywords, in: line.normalized) {
            let neighbors = lines.indices.filter { abs($0 - index) == 1 }.map { lines[$0] }
            if let amount = neighbors.flatMap({ amounts(in: $0.text) }).max() {
                return amount
            }
        }

        let lowerThird = lines.filter { $0.midYFromTop >= 0.62 }
        let candidates = (lowerThird.isEmpty ? lines : lowerThird)
            .filter { !containsAny(ignoreAmountKeywords, in: $0.normalized) }
            .filter { !containsAny(["bar gegeben", "gegeben", "rueckgeld", "wechselgeld"], in: $0.normalized) }
            .flatMap { amounts(in: $0.text) }
            .filter { $0 >= Decimal(string: "0.50")! && $0 <= Decimal(string: "99999.99")! }

        return candidates.max()
    }

    static func inferDate(from lines: [Line]) -> Date? {
        let parsed = lines.compactMap { parseDate(in: $0.text) }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let plausible = parsed.filter { date in
            let day = calendar.startOfDay(for: date)
            guard let earliest = calendar.date(byAdding: .year, value: -3, to: today) else { return false }
            return day >= earliest && day <= today
        }
        return plausible.last ?? parsed.last
    }

    static func inferTitle(from lines: [Line]) -> String? {
        let header = lines.filter { $0.midYFromTop <= 0.38 }
        let pool = header.isEmpty ? Array(lines.prefix(8)) : header

        for line in pool {
            if let title = cleanedTitle(line.text) {
                return title
            }
        }
        return nil
    }

    static func cleanedTitle(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...42).contains(text.count) else { return nil }

        let lower = text.lowercased()
        let skipSnippets = [
            "gmbh", "str.", "straße", "strasse", "platz", "allee", "weg ",
            "tel", "telefon", "fax", "www", "http", ".de", "@",
            "ust-id", "ust idnr", "steuernr", "steuernummer", "filiale",
            "kasse", "bon-nr", "beleg", "uid", "sepa", "iban", "blz",
            "opening", "geöffnet", "mo-fr", "mo -"
        ]
        if skipSnippets.contains(where: { lower.contains($0) }) { return nil }
        if text.range(of: #"^\d{5}\b"#, options: .regularExpression) != nil { return nil }
        if parseDate(in: text) != nil { return nil }
        if amounts(in: text).isEmpty == false, text.split(separator: " ").count <= 2 { return nil }

        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 3 else { return nil }

        return text
    }

    static func amounts(in text: String) -> [Decimal] {
        let pattern = #"(?:EUR|EURO|€)?\s*(\d{1,5}(?:[.\s]\d{3})*[,.]\d{2}|\d{1,5})\s*(?:EUR|EURO|€)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match -> Decimal? in
            let raw = ns.substring(with: match.range(at: 1))
                .replacingOccurrences(of: " ", with: "")
            return parseDecimal(raw)
        }
        .filter { $0 > 0 }
    }

    static func parseDecimal(_ raw: String) -> Decimal? {
        if let comma = raw.lastIndex(of: ","), raw.distance(from: comma, to: raw.endIndex) == 3 {
            let normalized = raw
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
            return Decimal(string: normalized)
        }
        if let dot = raw.lastIndex(of: "."), raw.distance(from: dot, to: raw.endIndex) == 3 {
            return Decimal(string: raw.replacingOccurrences(of: ",", with: ""))
        }
        if raw.contains(",") || raw.contains(".") {
            return nil
        }
        if let value = Decimal(string: raw), value >= 10 {
            return value
        }
        return nil
    }

    static func parseDate(in text: String) -> Date? {
        let patterns = [
            #"(\d{1,2})\.(\d{1,2})\.(\d{4})"#,
            #"(\d{1,2})\.(\d{1,2})\.(\d{2})"#,
            #"(\d{4})-(\d{2})-(\d{2})"#
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }

            let a = Int(ns.substring(with: match.range(at: 1))) ?? 0
            let b = Int(ns.substring(with: match.range(at: 2))) ?? 0
            let c = Int(ns.substring(with: match.range(at: 3))) ?? 0

            let day: Int
            let month: Int
            let year: Int
            if index == 2 {
                year = a
                month = b
                day = c
            } else {
                day = a
                month = b
                year = c < 100 ? 2000 + c : c
            }

            var components = DateComponents()
            components.day = day
            components.month = month
            components.year = year
            if let date = Calendar.current.date(from: components) {
                return date
            }
        }
        return nil
    }

    static func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}

private extension UIImage {
    func preparedForOCR(maxDimension: CGFloat = 2200) -> UIImage {
        let longest = max(size.width, size.height)
        let scaleFactor = longest > maxDimension ? maxDimension / longest : 1
        let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
