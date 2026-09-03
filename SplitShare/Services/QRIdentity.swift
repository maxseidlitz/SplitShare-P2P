import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

enum QRIdentity {
    static let prefix = "splitshare:"

    struct Payload: Codable, Equatable {
        var v: Int
        var profileId: UUID
        var deviceId: String
        var displayName: String

        enum CodingKeys: String, CodingKey {
            case v
            case profileId = "p"
            case deviceId = "d"
            case displayName = "n"
        }
    }

    static func payload(profileId: UUID, deviceId: String, displayName: String) -> Payload {
        Payload(v: 1, profileId: profileId, deviceId: deviceId, displayName: displayName)
    }

    static func encode(_ payload: Payload) -> String? {
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return prefix + json
    }

    static func decode(_ raw: String) -> Payload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = trimmed.hasPrefix(prefix) ? String(trimmed.dropFirst(prefix.count)) : trimmed
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func image(from payload: Payload, dimension: CGFloat = 512) -> UIImage? {
        guard let string = encode(payload),
              let data = string.data(using: .utf8) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scale = dimension / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
