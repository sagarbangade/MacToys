import Foundation
import ScreenCaptureKit

@MainActor
func getFilter(display: SCDisplay, shareableContent: SCShareableContent) -> SCContentFilter {
    let currentPID = NSRunningApplication.current.processIdentifier
    let appsToExclude = shareableContent.applications.filter { $0.processID == currentPID }
    return SCContentFilter(display: display, excludingApplications: appsToExclude, exceptingWindows: [])
}
