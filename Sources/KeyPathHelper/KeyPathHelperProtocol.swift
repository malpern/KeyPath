import Foundation

@objc(KeyPathHelperProtocol)
protocol KeyPathHelperProtocol {
    func reloadKanataConfig(configPath: String, withReply reply: @escaping (Bool, String?) -> Void)
    func restartKanataService(withReply reply: @escaping (Bool, String?) -> Void)
    func getHelperVersion(withReply reply: @escaping (String) -> Void)
}