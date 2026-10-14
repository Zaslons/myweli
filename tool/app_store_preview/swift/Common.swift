// Shared by the four helpers of tool/app_store_preview (see README.md).
// Compiled with `xcrun swiftc -O -parse-as-library Common.swift <Tool>.swift`;
// there is no package manager and no dependency outside the macOS SDK.

import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Files a helper has begun to write. If it stops, they go: a refused or
/// failed run must not leave something that looks like a result.
nonisolated(unsafe) var unfinished: [String] = []

/// Stop with one line on stderr. A helper never returns a half-result.
func die(_ msg: String) -> Never {
  for path in unfinished {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let scratch = url.lastPathComponent + ".sb-"
    let folder = url.deletingLastPathComponent()
    for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    where name.hasPrefix(scratch) {
      try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
  }
  FileHandle.standardError.write(Data("\(toolName): \(msg)\n".utf8))
  exit(1)
}

var toolName: String { (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "tool" }

/// `--name value` pairs and bare words, in order. Unknown flags are refused by
/// the caller (`finish`), so a typo cannot silently fall back to a default.
struct Args {
  private var flags: [String: String] = [:]
  private(set) var words: [String] = []
  private var used = Set<String>()

  init(_ argv: [String]) {
    var i = 0
    while i < argv.count {
      let a = argv[i]
      if a.hasPrefix("--") {
        guard i + 1 < argv.count else { die("flag \(a) needs a value") }
        flags[String(a.dropFirst(2))] = argv[i + 1]
        i += 2
      } else {
        words.append(a)
        i += 1
      }
    }
  }

  mutating func opt(_ name: String) -> String? {
    used.insert(name)
    return flags[name]
  }

  mutating func req(_ name: String) -> String {
    guard let v = opt(name) else { die("missing --\(name)") }
    return v
  }

  mutating func int(_ name: String, _ fallback: Int? = nil) -> Int {
    guard let s = opt(name) else {
      guard let f = fallback else { die("missing --\(name)") }
      return f
    }
    guard let v = Int(s) else { die("--\(name) is not an integer: \(s)") }
    return v
  }

  func finish() {
    for k in flags.keys where !used.contains(k) { die("unknown flag --\(k)") }
  }
}

func writeJSON(_ obj: Any, to path: String) {
  guard
    let data = try? JSONSerialization.data(
      withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
  else { die("cannot serialise JSON for \(path)") }
  do { try data.write(to: URL(fileURLWithPath: path)) } catch { die("cannot write \(path): \(error)") }
}

func readJSON(_ path: String) -> [String: Any] {
  guard let data = FileManager.default.contents(atPath: path) else { die("cannot read \(path)") }
  guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    die("\(path) is not a JSON object")
  }
  return obj
}

func fourCC(_ code: FourCharCode) -> String {
  let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
  return String(bytes: bytes, encoding: .macOSRoman) ?? "\(code)"
}

/// Exact conversion of a CMTime to integer ticks of `timescale`; refuses a time
/// that does not land on a tick rather than rounding it.
func ticks(_ t: CMTime, _ timescale: Int32, _ what: String) -> Int64 {
  guard t.isValid, !t.isIndefinite else { die("\(what): invalid time") }
  if t.timescale == timescale { return t.value }
  let c = CMTimeConvertScale(t, timescale: timescale, method: .roundHalfAwayFromZero)
  guard CMTimeCompare(c, t) == 0 else {
    die("\(what): \(t.value)/\(t.timescale) is not a whole number of 1/\(timescale) s")
  }
  return c.value
}

// MARK: - pixels

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// A decoded frame as tightly packed BGRA bytes (alpha ignored).
struct Frame {
  let width: Int
  let height: Int
  var bgra: [UInt8]

  init(_ pb: CVPixelBuffer) {
    guard CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA else {
      die("decoder returned \(fourCC(CVPixelBufferGetPixelFormatType(pb))), expected BGRA")
    }
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
    width = CVPixelBufferGetWidth(pb)
    height = CVPixelBufferGetHeight(pb)
    let stride = CVPixelBufferGetBytesPerRow(pb)
    guard let base = CVPixelBufferGetBaseAddress(pb) else { die("pixel buffer has no base address") }
    bgra = [UInt8](repeating: 0, count: width * height * 4)
    let w4 = width * 4
    bgra.withUnsafeMutableBytes { dst in
      for y in 0..<height {
        memcpy(dst.baseAddress! + y * w4, base + y * stride, w4)
      }
    }
  }

  /// PNG, RGB without alpha, written as the bytes are (tagged sRGB, never
  /// converted).
  func writePNG(_ path: String) {
    var rgb = [UInt8](repeating: 0, count: width * height * 3)
    bgra.withUnsafeBufferPointer { s in
      rgb.withUnsafeMutableBufferPointer { d in
        var i = 0
        var o = 0
        for _ in 0..<(width * height) {
          d[o] = s[i + 2]
          d[o + 1] = s[i + 1]
          d[o + 2] = s[i]
          i += 4
          o += 3
        }
      }
    }
    guard let provider = CGDataProvider(data: Data(rgb) as CFData),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
        bytesPerRow: width * 3, space: sRGB,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { die("cannot build an image for \(path)") }
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    else { die("cannot open \(path) for writing") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { die("cannot write \(path)") }
  }
}

/// Decode a PNG to tightly packed BGRA, byte for byte (no colour conversion:
/// the bitmap context uses the image's own colour space).
func readPNG(_ path: String) -> (width: Int, height: Int, bgra: [UInt8]) {
  guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
  else { die("cannot read image \(path)") }
  let w = image.width
  let h = image.height
  var out = [UInt8](repeating: 0, count: w * h * 4)
  let space = (image.colorSpace?.model == .rgb ? image.colorSpace : nil) ?? sRGB
  let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
  out.withUnsafeMutableBytes { buf in
    guard
      let ctx = CGContext(
        data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: space, bitmapInfo: info)
    else { die("cannot make a bitmap for \(path)") }
    ctx.interpolationQuality = .none
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
  }
  return (w, h, out)
}

// MARK: - reading a movie

struct VideoTrackInfo {
  let track: AVAssetTrack
  let timescale: Int32
  let width: Int
  let height: Int
}

func loadVideoTrack(_ asset: AVAsset, _ path: String) async -> VideoTrackInfo {
  let tracks: [AVAssetTrack]
  do { tracks = try await asset.loadTracks(withMediaType: .video) } catch {
    die("cannot open \(path): \(error.localizedDescription)")
  }
  guard tracks.count == 1 else { die("\(path) has \(tracks.count) video tracks, expected 1") }
  let t = tracks[0]
  do {
    let scale = try await t.load(.naturalTimeScale)
    let size = try await t.load(.naturalSize)
    return VideoTrackInfo(
      track: t, timescale: scale, width: Int(size.width.rounded()), height: Int(size.height.rounded()))
  } catch { die("cannot read the video track of \(path): \(error.localizedDescription)") }
}

/// Decode every frame in presentation order and hand it to `body` with its
/// presentation time in ticks of the track's timescale. Stops when `body`
/// returns false.
func decodeFrames(
  _ asset: AVAsset, _ info: VideoTrackInfo, _ path: String,
  _ body: (_ index: Int, _ pts: Int64, _ pb: CVPixelBuffer) -> Bool
) {
  let reader: AVAssetReader
  do { reader = try AVAssetReader(asset: asset) } catch { die("cannot read \(path): \(error)") }
  let out = AVAssetReaderTrackOutput(
    track: info.track,
    outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
  out.alwaysCopiesSampleData = false
  guard reader.canAdd(out) else { die("cannot decode the video track of \(path)") }
  reader.add(out)
  guard reader.startReading() else {
    die("cannot start decoding \(path): \(reader.error?.localizedDescription ?? "unknown")")
  }
  var index = 0
  var last: Int64 = -1
  while let sb = out.copyNextSampleBuffer() {
    guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
    let pts = ticks(CMSampleBufferGetPresentationTimeStamp(sb), info.timescale, "frame \(index)")
    guard pts > last else {
      die("frame \(index) is not after the one before (\(pts) <= \(last)): frames out of order")
    }
    last = pts
    let more = body(index, pts, pb)
    index += 1
    if !more {
      reader.cancelReading()
      return
    }
  }
  if reader.status == .failed {
    die("decoding \(path) failed: \(reader.error?.localizedDescription ?? "unknown")")
  }
}
