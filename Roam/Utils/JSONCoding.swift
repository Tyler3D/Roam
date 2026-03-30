import Foundation

private func parseRoamISO8601(_ str: String) -> Date? {
    let withFrac = ISO8601DateFormatter()
    withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = withFrac.date(from: str) { return d }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    if let d = plain.date(from: str) { return d }
    // Handle naive datetimes (no timezone suffix) from backend — treat as UTC
    let naive = ISO8601DateFormatter()
    naive.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
    naive.timeZone = TimeZone(identifier: "UTC")
    if let d = naive.date(from: str) { return d }
    // Naive with fractional seconds
    let naiveFrac = ISO8601DateFormatter()
    naiveFrac.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withFractionalSeconds]
    naiveFrac.timeZone = TimeZone(identifier: "UTC")
    return naiveFrac.date(from: str)
}

extension JSONDecoder {
    /// Decodes FastAPI / Pydantic datetimes and camelCase keys matching backend models.
    static let roam: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = parseRoamISO8601(str) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }
        return d
    }()
}

extension JSONEncoder {
    static let roam: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
