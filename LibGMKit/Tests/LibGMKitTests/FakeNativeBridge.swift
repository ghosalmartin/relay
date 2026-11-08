import Foundation
@testable import LibGMKit
import Synchronization

/// Records calls and replays scripted responses, standing in for the Go library.
final class FakeNativeBridge: NativeBridge {
    let rawEvents: AsyncStream<(kind: Int32, payload: Data)>
    private let continuation: AsyncStream<(kind: Int32, payload: Data)>.Continuation
    private let log = Mutex<[String]>([])
    private let responses = Mutex<[BridgeMethod: Result<Data, LibGMError>]>([:])

    init() {
        (rawEvents, continuation) = AsyncStream.makeStream(of: (kind: Int32, payload: Data).self)
    }

    var calls: [String] { log.withLock { $0 } }

    func emit(kind: Int32, payload: Data = Data()) { continuation.yield((kind, payload)) }
    func respond(to method: BridgeMethod, with result: Result<Data, LibGMError>) {
        responses.withLock { $0[method] = result }
    }

    func startQRPairing() throws(LibGMError) { record("startQRPairing") }
    func refreshQRCode() throws(LibGMError) { record("refreshQRCode") }
    func startGoogleAccountPairing(cookiesJSON: Data) throws(LibGMError) {
        record("google:" + String(decoding: cookiesJSON, as: UTF8.self))
    }
    func connect() throws(LibGMError) { record("connect") }
    func disconnect() { record("disconnect") }
    func unpair() throws(LibGMError) { record("unpair") }

    func call(_ method: BridgeMethod, request: Data) throws(LibGMError) -> Data {
        record("call:\(method):" + String(decoding: request, as: UTF8.self))
        return try (responses.withLock { $0[method] } ?? .success(Data())).get()
    }

    func close() {
        record("close")
        continuation.finish()
    }

    private func record(_ entry: String) { log.withLock { $0.append(entry) } }
}
