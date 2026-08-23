import CoreGraphics
import MonitorCore

extension ExternalDisplay {
    /// Report input filled with everything discovery knows; callers add DDC state.
    public func reportInput(name: String? = nil, ddcStatus: DDCStatus, controlMethod: String,
                            profile: DDCProfile? = nil, capabilities: Capabilities? = nil,
                            values: [UInt8: VCPValue] = [:]) -> DisplayReport.Input {
        var input = DisplayReport.Input(name: name ?? self.name, ddcStatus: ddcStatus.summary, controlMethod: controlMethod)
        input.displayID = displayID
        input.isMain = isMain
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            let scaled = mode.pixelWidth != mode.width
            input.resolution = "\(mode.width) x \(mode.height)" + (scaled ? " (rendered at \(mode.pixelWidth) x \(mode.pixelHeight))" : "")
            input.refreshRate = mode.refreshRate
        }
        input.transportUpstream = avService?.transportUpstream
        input.transportDownstream = avService?.transportDownstream
        input.productName = avService?.productName
        input.alphanumericSerial = avService?.alphanumericSerial
        input.edid = edid
        input.ddcFraming = profile?.description
        input.capabilities = capabilities
        input.values = values
        return input
    }
}
