//
//  videodecoder-rgb.swift
//
//  RGB format conversion to BGRA using FFmpeg swscale.
//

import CoreVideo
import Foundation
import MediaExtension

extension VideoDecoder {

    // Convert RGB-like AVFrame formats directly to BGRA using swscale.
    func RGBConvertToBGRA(frame: inout AVFrame, pixelBuffer: inout CVPixelBuffer) -> CustomNSError? {
        let srcFormat = AVPixelFormat(frame.format)

        guard let desc = av_pix_fmt_desc_get(srcFormat)?.pointee,
            (desc.flags & UInt64(AV_PIX_FMT_FLAG_RGB)) != 0, srcFormat != AV_PIX_FMT_PAL8
        else {
            return CVReturnError(errorCode: Int(kCVReturnUnsupported), context: "RGBConvertToBGRA")
        }

        let srcWidth = Int(frame.width)
        let srcHeight = Int(frame.height)
        let dstWidth = CVPixelBufferGetWidth(pixelBuffer)
        let dstHeight = CVPixelBufferGetHeight(pixelBuffer)

        sws_ctx = sws_getCachedContext(
            sws_ctx,
            Int32(srcWidth),
            Int32(srcHeight),
            srcFormat,
            Int32(dstWidth),
            Int32(dstHeight),
            AV_PIX_FMT_BGRA,
            Int32(SWS_BILINEAR.rawValue|SWS_FULL_CHR_H_INT.rawValue),
            nil,
            nil,
            nil
        )
        guard sws_ctx != nil else {
            return AVERROR(errorCode: ENOMEM, context: "sws_getCachedContext")
        }

        let status = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard status == kCVReturnSuccess,
              let dstData = CVPixelBufferGetBaseAddress(pixelBuffer)
        else {
            return CVReturnError(errorCode: Int(status), context: "CVPixelBufferLockBaseAddress")
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        // Packed BGRA output uses only plane 0.
        var dstPlane0: UnsafeMutablePointer<UInt8>? = dstData.assumingMemoryBound(to: UInt8.self)
        var dstStride0 = Int32(CVPixelBufferGetBytesPerRow(pixelBuffer))

        let outHeight = withUnsafePointer(to: &frame.linesize) { srcLinesizeTuple in
            srcLinesizeTuple.withMemoryRebound(to: Int32.self, capacity: Int(AV_NUM_DATA_POINTERS)) { srcLinesizePtr in
                withUnsafeMutablePointer(to: &dstPlane0) { dstDataPtr in
                    withUnsafePointer(to: &dstStride0) { dstLinesizePtr in
                        sws_scale(
                            sws_ctx,
                            UnsafePointer<UnsafePointer<UInt8>?>(OpaquePointer(frame.extended_data)),
                            srcLinesizePtr,
                            0,
                            Int32(srcHeight),
                            dstDataPtr,
                            dstLinesizePtr
                        )
                    }
                }
            }
        }

        guard outHeight > 0 else {
            return AVERROR(errorCode: Int32(outHeight), context: "sws_scale")
        }

        return nil
    }
}
