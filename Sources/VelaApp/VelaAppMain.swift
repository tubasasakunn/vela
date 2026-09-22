import AppKit
import VelaCore

@main
struct VelaAppMain {
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let currentProcess = NSRunningApplication.current.processIdentifier
        let previousInstances = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.vela.app")
            .filter { $0.processIdentifier != currentProcess }
        previousInstances.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(1)
        while previousInstances.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        }
        let delegate = VelaDelegate()
        application.delegate = delegate
        application.run()
    }
}
