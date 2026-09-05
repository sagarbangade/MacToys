import AppKit

class MyWindow: NSPanel {
    override func keyDown(with event: NSEvent) {
        print(event.keyCode)
        super.keyDown(with: event)
    }
}
