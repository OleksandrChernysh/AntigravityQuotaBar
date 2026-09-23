import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Runs strictly as a background/menu bar accessory, no dock icon
app.run()
