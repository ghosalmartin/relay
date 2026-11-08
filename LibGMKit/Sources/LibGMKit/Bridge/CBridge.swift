import Foundation
import GMBridgeC
import Synchronization

/// `NativeBridge` backed by the Go static library (GMBridge.xcframework).
final class CBridge: NativeBridge {
    let rawEvents: AsyncStream<(kind: Int32, payload: Data)>
    private let relay: EventRelay
    private let handle: Int64

    /// - Throws: `LibGMError.invalidSavedSession` if the Go side could not decode it.
    init(savedSession: Data?) throws(LibGMError) {
        let (stream, continuation) = AsyncStream.makeStream(of: (kind: Int32, payload: Data).self)
        let relay = EventRelay(continuation)
        let context = Unmanaged.passRetained(relay).toOpaque()   // balanced in close()
        let handle = Self.withBytes(savedSession ?? Data()) { bytes, count in
            gm_session_new(bytes, count, cEventCallback, context)
        }
        guard handle > 0 else {
            Unmanaged<EventRelay>.fromOpaque(context).release()
            throw .invalidSavedSession
        }
        self.rawEvents = stream
        self.relay = relay
        self.handle = handle
    }

    func startQRPairing() throws(LibGMError) {
        _ = try invoke { gm_start_qr_pairing(handle, $0, $1) }
    }

    func refreshQRCode() throws(LibGMError) {
        _ = try invoke { gm_refresh_qr(handle, $0, $1) }
    }

    func startGoogleAccountPairing(cookiesJSON: Data) throws(LibGMError) {
        _ = try invoke { out, outLength in
            Self.withBytes(cookiesJSON) { gm_start_google_pairing(handle, $0, $1, out, outLength) }
        }
    }

    func connect() throws(LibGMError) {
        _ = try invoke { gm_connect(handle, $0, $1) }
    }

    func disconnect() {
        gm_disconnect(handle)
    }

    func unpair() throws(LibGMError) {
        _ = try invoke { gm_unpair(handle, $0, $1) }
    }

    func call(_ method: BridgeMethod, request: Data) throws(LibGMError) -> Data {
        try invoke { out, outLength in
            Self.withBytes(request) { gm_call(handle, method.rawValue, $0, $1, out, outLength) }
        }
    }

    func close() {
        gm_session_free(handle)                                 // after this, Go never calls back
        relay.finish()
        Unmanaged.passUnretained(relay).release()               // balances passRetained in init
    }

    /// Runs one bridge function and turns its out-buffer into a result.
    private func invoke(
        _ function: (UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, UnsafeMutablePointer<Int64>) -> Int32
    ) throws(LibGMError) -> Data {
        var out: UnsafeMutablePointer<UInt8>?
        var outLength: Int64 = 0
        let status = function(&out, &outLength)
        let bytes = out.map { Data(bytes: $0, count: Int(outLength)) } ?? Data()
        if let out { gm_free(out) }
        guard status == 0 else {
            throw .bridge(String(decoding: bytes, as: UTF8.self))
        }
        return bytes
    }

    private static func withBytes<R>(_ data: Data, _ body: (UnsafeMutablePointer<UInt8>?, Int64) -> R) -> R {
        var copy = data   // the C side takes a mutable pointer but never writes
        return copy.withUnsafeMutableBytes { buffer in
            body(buffer.bindMemory(to: UInt8.self).baseAddress, Int64(buffer.count))
        }
    }
}

/// Receives C callbacks on Go threads and forwards them into the event stream.
private final class EventRelay: Sendable {
    private let continuation: AsyncStream<(kind: Int32, payload: Data)>.Continuation

    init(_ continuation: AsyncStream<(kind: Int32, payload: Data)>.Continuation) {
        self.continuation = continuation
    }

    func deliver(kind: Int32, payload: Data) {
        continuation.yield((kind, payload))
    }

    func finish() {
        continuation.finish()
    }
}

/// The C function pointer handed to the bridge. Copies the payload: it is only
/// valid for the duration of the call.
private let cEventCallback: gm_event_cb = { context, kind, data, length in
    guard let context else { return }
    let payload = (data != nil && length > 0) ? Data(bytes: data!, count: Int(length)) : Data()
    Unmanaged<EventRelay>.fromOpaque(context).takeUnretainedValue().deliver(kind: kind, payload: payload)
}
