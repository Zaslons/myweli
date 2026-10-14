// inspect — what AVFoundation reads back from a written movie. verify.py
// compares this with its own parse of the file's boxes and with avmediainfo;
// it is the only one of the three that decodes pictures and sound.
//
//   inspect facts  <movie> --out facts.json
//       Tracks, formats, every video sample's time and duration, the decoded
//       sound's peak.
//   inspect frames <movie> --indices 0,15,540 --out <dir>
//       Decode the listed frames (presentation order, from 0) to
//       <dir>/frame_NNNNNN.png.

import AVFoundation
import CoreMedia
import Foundation

func pair(_ t: CMTime) -> [Int] { [Int(t.value), Int(t.timescale)] }

func videoFacts(_ asset: AVAsset, _ track: AVAssetTrack, _ path: String) async -> [String: Any] {
  var out: [String: Any] = [:]
  do {
    let size = try await track.load(.naturalSize)
    let transform = try await track.load(.preferredTransform)
    let scale = try await track.load(.naturalTimeScale)
    let range = try await track.load(.timeRange)
    out["natural_size"] = [Double(size.width), Double(size.height)]
    out["transform"] = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].map { Double($0) }
    out["timescale"] = Int(scale)
    out["nominal_fps"] = Double(try await track.load(.nominalFrameRate))
    out["min_frame_duration"] = pair(try await track.load(.minFrameDuration))
    out["data_rate_bps"] = Double(try await track.load(.estimatedDataRate))
    out["sample_bytes"] = Int(try await track.load(.totalSampleDataLength))
    out["time_range"] = [pair(range.start), pair(range.duration)]
    out["requires_frame_reordering"] = try await track.load(.requiresFrameReordering)
    let formats = try await track.load(.formatDescriptions)
    out["format_count"] = formats.count
    if let fd = formats.first {
      out["codec"] = fourCC(CMFormatDescriptionGetMediaSubType(fd))
      let dims = CMVideoFormatDescriptionGetDimensions(fd)
      out["coded_size"] = [Int(dims.width), Int(dims.height)]
      let ext = CMFormatDescriptionGetExtensions(fd) as? [String: Any] ?? [:]
      var kept: [String: Any] = [:]
      for (k, v) in ext {
        // plain values only; the avcC atom is parsed by verify.py from the file
        if v is NSNumber || v is NSString {
          kept[k] = v
        } else if let d = v as? [String: Any], d.values.allSatisfy({ $0 is NSNumber || $0 is NSString }) {
          kept[k] = d
        }
      }
      out["extensions"] = kept
    }

    // Every sample as stored: presentation time and duration.
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else { die("cannot read the samples of \(path)") }
    var pts: [Int64] = []
    var durations: [String: Int] = [:]
    var decodeOrderIsPresentationOrder = true
    var last: Int64 = -1
    while let sb = output.copyNextSampleBuffer() {
      guard CMSampleBufferGetNumSamples(sb) > 0 else { continue }
      let t = ticks(CMSampleBufferGetPresentationTimeStamp(sb), scale, "sample \(pts.count)")
      let d = ticks(CMSampleBufferGetDuration(sb), scale, "duration of sample \(pts.count)")
      if t <= last { decodeOrderIsPresentationOrder = false }
      last = t
      pts.append(t)
      durations[String(d), default: 0] += 1
    }
    pts.sort()
    out["samples"] = [
      "count": pts.count, "durations": durations, "pts": pts,
      "decode_order_is_presentation_order": decodeOrderIsPresentationOrder,
    ]
  } catch { die("cannot read the video track of \(path): \(error.localizedDescription)") }
  return out
}

func audioFacts(_ asset: AVAsset, _ track: AVAssetTrack, _ path: String) async -> [String: Any] {
  var out: [String: Any] = [:]
  do {
    let range = try await track.load(.timeRange)
    out["timescale"] = Int(try await track.load(.naturalTimeScale))
    out["data_rate_bps"] = Double(try await track.load(.estimatedDataRate))
    out["sample_bytes"] = Int(try await track.load(.totalSampleDataLength))
    out["time_range"] = [pair(range.start), pair(range.duration)]
    let formats = try await track.load(.formatDescriptions)
    out["format_count"] = formats.count
    if let fd = formats.first {
      out["codec"] = fourCC(CMFormatDescriptionGetMediaSubType(fd))
      if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
        out["sample_rate"] = asbd.mSampleRate
        out["channels"] = Int(asbd.mChannelsPerFrame)
        out["format_id"] = fourCC(asbd.mFormatID)
        out["format_flags"] = Int(asbd.mFormatFlags)  // for AAC: the MPEG-4 object type (2 = AAC-LC)
        out["frames_per_packet"] = Int(asbd.mFramesPerPacket)
      }
    }
    // Decode the whole track: sample count and the loudest sample.
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ])
    reader.add(output)
    guard reader.startReading() else { die("cannot decode the sound of \(path)") }
    var frames = 0
    var peak = 0
    while let sb = output.copyNextSampleBuffer() {
      guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
      let length = CMBlockBufferGetDataLength(block)
      var data = [Int16](repeating: 0, count: length / 2)
      let status = data.withUnsafeMutableBytes {
        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
      }
      guard status == noErr else { die("cannot read decoded sound (\(status))") }
      for v in data where abs(Int(v)) > peak { peak = abs(Int(v)) }
      frames += CMSampleBufferGetNumSamples(sb)
    }
    out["decoded"] = ["frames": frames, "peak": peak]
  } catch { die("cannot read the audio track of \(path): \(error.localizedDescription)") }
  return out
}

func facts(_ path: String, _ args: inout Args) async {
  let outPath = args.req("out")
  args.finish()
  let asset = AVURLAsset(url: URL(fileURLWithPath: path))
  var tracks: [[String: Any]] = []
  do {
    for track in try await asset.load(.tracks) {
      var row: [String: Any] = [
        "id": Int(track.trackID), "type": track.mediaType.rawValue,
        "enabled": try await track.load(.isEnabled),
      ]
      switch track.mediaType {
      case .video: row.merge(await videoFacts(asset, track, path)) { _, new in new }
      case .audio: row.merge(await audioFacts(asset, track, path)) { _, new in new }
      default: break
      }
      tracks.append(row)
    }
    let duration = try await asset.load(.duration)
    let size = (try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? -1
    writeJSON(["file_bytes": size, "duration": pair(duration), "tracks": tracks], to: outPath)
  } catch { die("cannot read \(path): \(error.localizedDescription)") }
  print("facts: \(tracks.count) tracks -> \(outPath)")
}

func frames(_ path: String, _ args: inout Args) async {
  let outDir = args.req("out")
  let list = args.req("indices")
  args.finish()
  let wanted = Set(
    list.split(separator: ",").map { s -> Int in
      guard let v = Int(s), v >= 0 else { die("--indices: `\(s)` is not a frame number") }
      return v
    })
  guard let last = wanted.max() else { die("--indices is empty") }
  let asset = AVURLAsset(url: URL(fileURLWithPath: path))
  let info = await loadVideoTrack(asset, path)
  do { try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true) } catch {
    die("cannot create \(outDir): \(error)")
  }
  var written = 0
  decodeFrames(asset, info, path) { index, _, pb in
    if wanted.contains(index) {
      Frame(pb).writePNG(String(format: "\(outDir)/frame_%06d.png", index))
      written += 1
    }
    return index < last
  }
  guard written == wanted.count else {
    die("\(path) has fewer than \(last + 1) frames: \(written) of \(wanted.count) written")
  }
  print("frames: \(written) -> \(outDir)")
}

@main
enum Inspect {
  static func main() async {
    var args = Args(Array(CommandLine.arguments.dropFirst()))
    guard args.words.count == 2 else { die("usage: inspect facts|frames <movie> --out ...") }
    let path = args.words[1]
    guard FileManager.default.fileExists(atPath: path) else { die("no such file: \(path)") }
    switch args.words[0] {
    case "facts": await facts(path, &args)
    case "frames": await frames(path, &args)
    default: die("unknown command `\(args.words[0])`")
    }
  }
}
