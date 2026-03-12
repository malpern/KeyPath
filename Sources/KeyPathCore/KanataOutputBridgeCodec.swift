import Foundation

public enum KanataOutputBridgeCodec {
    public static func encode(_ value: some Encodable) throws -> Data {
        let data = try JSONEncoder().encode(value)
        return data + Data([0x0A])
    }

    public static func decode<Response: Decodable>(_ data: Data, as _: Response.Type) throws
        -> Response
    {
        let payload =
            if data.last == 0x0A {
                data.dropLast()
            } else {
                data[...]
            }
        return try JSONDecoder().decode(Response.self, from: Data(payload))
    }
}
