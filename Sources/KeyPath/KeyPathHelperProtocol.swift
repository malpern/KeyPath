import Foundation

@objc(KeyPathHelperProtocol)
protocol KeyPathHelperProtocol {
    func reloadKanataConfig(configPath: String, withReply reply: @escaping (Bool, String?) -> Void)
    func restartKanataService(withReply reply: @escaping (Bool, String?) -> Void)
    func getHelperVersion(withReply reply: @escaping (String) -> Void)

    // New methods for direct Kanata process management
    func startKanata(withReply reply: @escaping (Bool, String?) -> Void)
    func stopKanata(withReply reply: @escaping (Bool, String?) -> Void)
}