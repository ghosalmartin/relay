import Foundation

/// The C functions LibGMKit needs from the Go bridge, as a protocol so the Swift
/// side can be tested without the native library.
///
/// Every call blocks the calling thread; `LibGMSession` makes them async.
protocol NativeBridge: Sendable {
    /// Payloads that arrive from the bridge, as raw (kind, bytes) pairs.
    var rawEvents: AsyncStream<(kind: Int32, payload: Data)> { get }

    func startQRPairing() throws(LibGMError)
    func refreshQRCode() throws(LibGMError)
    func startGoogleAccountPairing(cookiesJSON: Data) throws(LibGMError)
    func connect() throws(LibGMError)
    func disconnect()
    func unpair() throws(LibGMError)
    func call(_ method: BridgeMethod, request: Data) throws(LibGMError) -> Data
    /// Stops all callbacks. No event is delivered after this returns.
    func close()
}
