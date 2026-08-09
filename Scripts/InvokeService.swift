// End-to-end check of the "Proofread" macOS service: puts text on a private
// pasteboard, invokes the service exactly as a right-click would, and asserts
// the app (running with BULLETPROOF_FAKE_ENGINE=1) uppercased it.
// Retries while the freshly launched app's services port registers.
import AppKit

let input = "teh quick brwn fox jump over the lazi dog"
let expected = input.uppercased()

for attempt in 1...30 {
    let pboard = NSPasteboard(name: NSPasteboard.Name("bulletproof-e2e-\(attempt)"))
    pboard.clearContents()
    pboard.setString(input, forType: .string)
    if NSPerformService("Proofread", pboard),
       let output = pboard.string(forType: .string), output == expected {
        print("E2E OK (attempt \(attempt)): \(output)")
        exit(0)
    }
    print("attempt \(attempt) failed, retrying...")
    Thread.sleep(forTimeInterval: 2)
}
print("E2E FAILED: service never returned the expected transformation")
exit(1)
