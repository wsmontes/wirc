import Foundation

struct WOMReference: Codable, Equatable, Identifiable {
    var id: String
    var type: [String]?
    var name: String?
}
