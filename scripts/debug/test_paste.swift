import AppKit

let pb = NSPasteboard.general
pb.clearContents()

let data = try! Data(contentsOf: URL(fileURLWithPath: "/Users/sagar/ocean/mac powertoys/MacToys/Package.swift"))

pb.setPropertyList(["/Users/sagar/ocean/mac powertoys/MacToys/Package.swift"], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
let urls = [URL(fileURLWithPath: "/Users/sagar/ocean/mac powertoys/MacToys/Package.swift") as NSURL]
pb.writeObjects(urls)

print(pb.types ?? [])
