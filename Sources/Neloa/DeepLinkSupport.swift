import Foundation

enum NeloaDeepLink {
    static let scheme = "neloa"

    nonisolated static func runURL(workflowID: UUID) -> URL {
        URL(string: "\(scheme)://run/\(workflowID.uuidString)")!
    }

    nonisolated static func runWorkflowID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == "run",
              url.query == nil,
              url.fragment == nil else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 1 else { return nil }
        return UUID(uuidString: components[0])
    }
}
