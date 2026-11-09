/// Gets a phone answering again after it has stopped responding to this device.
public protocol PhoneWaker: Sendable {
    /// False until the user has done the one-off setup, without which waking can't work.
    var isSetUp: Bool { get }
    func markSetUp()
    func startWaking() async
    func stopWaking() async
    /// Removes whatever the setup left on this Mac.
    func forget() async
}
