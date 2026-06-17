import Foundation

enum WOMIDGenerator {
    static func generate(type: String) -> String {
        let uuid = UUID().uuidString.lowercased()
        return "urn:wom:\(type):\(uuid)"
    }
}
