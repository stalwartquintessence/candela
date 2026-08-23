// Private IOKit symbols that Apple Silicon Macs use for I2C/DDC to external displays.
// They are undocumented and could change in a future macOS release; this file is the only place
// that calls them, so there is exactly one place to update.

import Foundation
import IOKit
import MonitorCore

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ dataAddress: UInt32,
                         _ inputBuffer: UnsafeMutableRawPointer, _ inputBufferSize: UInt32) -> IOReturn

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ offset: UInt32,
                        _ outputBuffer: UnsafeMutableRawPointer, _ outputBufferSize: UInt32) -> IOReturn

/// DDC/CI transport over IOAVService I2C.
public final class IOAVTransport: DDCTransport {
    private let service: CFTypeRef

    public init(service: CFTypeRef) {
        self.service = service
    }

    public func write(_ bytes: [UInt8]) -> Int32 {
        var buffer = bytes
        return buffer.withUnsafeMutableBytes { raw in
            IOAVServiceWriteI2C(service, UInt32(DDCPacket.chipAddress), UInt32(DDCPacket.hostAddress),
                                raw.baseAddress!, UInt32(raw.count))
        }
    }

    public func read(into buffer: inout [UInt8], offset: UInt8) -> Int32 {
        buffer.withUnsafeMutableBytes { raw in
            IOAVServiceReadI2C(service, UInt32(DDCPacket.chipAddress), UInt32(offset),
                               raw.baseAddress!, UInt32(raw.count))
        }
    }
}

extension DDCChannel {
    /// A channel to the display behind an IOAVService handle from `DisplayDiscovery`.
    public convenience init(service: CFTypeRef, profile: DDCProfile = DDCProfile.candidates[0]) {
        self.init(transport: IOAVTransport(service: service), profile: profile)
    }
}
