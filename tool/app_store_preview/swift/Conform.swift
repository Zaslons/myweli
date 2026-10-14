// conform — read a raw simulator take.
//
//   conform scan   <take> --out scan.json [--soft N --strong N]
//       Every decoded frame, in presentation order: its presentation time and
//       how much of the screen differs from the frame before. This is the data
//       idle stretches and touch-downs are found from.
//
//   conform diff   <take> --pairs pairs.json --out diff.json
//       The same measure between two frames that are not neighbours: the
//       picture held before a cut against the picture the film resumes on.
//
//   conform export <take> --segments segments.json --out <dir>
//       The kept source ranges resampled to a constant frame rate by
//       frame-hold: film frame n shows the last source frame presented at or
//       before its instant. Never a blend, never a change of speed. Each source
//       frame that is used is written once (src_NNNNNN.png); manifest.json says
//       which one every film frame shows.
//
// Times are integer ticks of the take's own timescale; nothing is rounded.

import AVFoundation
import CoreVideo
import Foundation

/// Two counts per frame, against the frame before it:
///   soft    pixels whose strongest channel moved by more than `softLevel`
///   strong  pixels whose strongest channel moved by more than `strongLevel`
/// plus the box that holds every strong pixel. The recording is lossy H.264:
/// a still screen decodes to values that wobble by a few levels and the
/// encoder keeps refining a picture after it stops moving, so a raw "any byte
/// differs" test would call every frame a change. What counts as a change is
/// decided from these numbers in edit.py, in one place.
let defaultSoftLevel = 16
let defaultStrongLevel = 64

struct Change {
  var soft = 0
  var strong = 0
  var maxDiff = 0
  var x0 = Int.max
  var y0 = Int.max
  var x1 = -1
  var y1 = -1

  var json: [String: Any] {
    var row: [String: Any] = ["soft": soft, "strong": strong, "max": maxDiff]
    if strong > 0 { row["box"] = [x0, y0, x1 + 1, y1 + 1] }
    return row
  }
}

func compare(_ a: Frame, _ b: Frame, soft: Int, strong: Int) -> Change {
  guard a.width == b.width, a.height == b.height else {
    die("frame size changed inside the take: \(a.width)x\(a.height) then \(b.width)x\(b.height)")
  }
  var c = Change()
  let w = a.width
  let h = a.height
  a.bgra.withUnsafeBufferPointer { pa in
    b.bgra.withUnsafeBufferPointer { pb in
      var i = 0
      for y in 0..<h {
        var rowStrong = false
        for x in 0..<w {
          let d0 = abs(Int(pa[i]) - Int(pb[i]))
          let d1 = abs(Int(pa[i + 1]) - Int(pb[i + 1]))
          let d2 = abs(Int(pa[i + 2]) - Int(pb[i + 2]))
          let d = max(d0, max(d1, d2))
          i += 4
          if d > c.maxDiff { c.maxDiff = d }
          if d > soft {
            c.soft += 1
            if d > strong {
              c.strong += 1
              rowStrong = true
              if x < c.x0 { c.x0 = x }
              if x > c.x1 { c.x1 = x }
            }
          }
        }
        if rowStrong {
          if y < c.y0 { c.y0 = y }
          c.y1 = y
        }
      }
    }
  }
  return c
}

func levels(_ args: inout Args) -> (soft: Int, strong: Int) {
  let soft = args.int("soft", defaultSoftLevel)
  let strong = args.int("strong", defaultStrongLevel)
  guard 0 <= soft, soft < strong, strong <= 254 else { die("need 0 <= --soft < --strong <= 254") }
  return (soft, strong)
}

func scan(_ path: String, _ args: inout Args) async {
  let outPath = args.req("out")
  let lv = levels(&args)
  args.finish()

  let asset = AVURLAsset(url: URL(fileURLWithPath: path))
  let info = await loadVideoTrack(asset, path)
  let audio = (try? await asset.loadTracks(withMediaType: .audio).count) ?? 0
  let duration = (try? await asset.load(.duration)) ?? .invalid
  let fps = (try? await info.track.load(.nominalFrameRate)) ?? 0
  var codec = "?"
  if let fd = try? await info.track.load(.formatDescriptions).first {
    codec = fourCC(CMFormatDescriptionGetMediaSubType(fd))
  }

  var frames: [[String: Any]] = []
  var previous: Frame?
  decodeFrames(asset, info, path) { index, pts, pb in
    let frame = Frame(pb)
    var row: [String: Any] = ["i": index, "pts": pts]
    // The first frame has nothing before it: it is recorded as no change.
    let c = previous.map { compare($0, frame, soft: lv.soft, strong: lv.strong) } ?? Change()
    row.merge(c.json) { _, new in new }
    frames.append(row)
    previous = frame
    return true
  }
  guard !frames.isEmpty else { die("\(path) has no decodable frame") }

  writeJSON(
    [
      "video": [
        "width": info.width, "height": info.height, "timescale": Int(info.timescale),
        "codec": codec, "nominal_fps": Double(fps), "audio_tracks": audio,
        "duration_ticks": ticks(
          CMTimeConvertScale(duration, timescale: info.timescale, method: .roundHalfAwayFromZero),
          info.timescale, "duration"),
      ],
      "levels": ["soft": lv.soft, "strong": lv.strong],
      "frames": frames,
    ], to: outPath)
  print("scan: \(frames.count) frames, \(info.width)x\(info.height), timescale \(info.timescale) -> \(outPath)")
}

/// Compare pairs of frames that are not neighbours — the picture held before
/// a cut against the picture the film resumes on.
func diff(_ path: String, _ args: inout Args) async {
  let pairsPath = args.req("pairs")
  let outPath = args.req("out")
  let lv = levels(&args)
  args.finish()
  guard let raw = readJSON(pairsPath)["pairs"] as? [[Int]] else { die("\(pairsPath): missing `pairs`") }
  for p in raw where p.count != 2 || p[0] < 0 || p[1] < p[0] {
    die("\(pairsPath): a pair is [earlier, later] frame numbers, got \(p)")
  }
  let asset = AVURLAsset(url: URL(fileURLWithPath: path))
  let info = await loadVideoTrack(asset, path)
  let wanted = Set(raw.flatMap { $0 })
  let last = wanted.max() ?? -1
  var kept: [Int: Frame] = [:]
  decodeFrames(asset, info, path) { index, _, pb in
    if wanted.contains(index) { kept[index] = Frame(pb) }
    return index < last
  }
  var out: [[String: Any]] = []
  for p in raw {
    guard let a = kept[p[0]], let b = kept[p[1]] else {
      die("the take has no frame \(kept[p[0]] == nil ? p[0] : p[1])")
    }
    var row = compare(a, b, soft: lv.soft, strong: lv.strong).json
    row["a"] = p[0]
    row["b"] = p[1]
    out.append(row)
  }
  writeJSON(["levels": ["soft": lv.soft, "strong": lv.strong], "pairs": out], to: outPath)
  print("diff: \(out.count) pairs -> \(outPath)")
}

/// Presentation times of every sample, sorted, without decoding.
func presentationTimes(_ asset: AVAsset, _ info: VideoTrackInfo, _ path: String) -> [Int64] {
  let reader: AVAssetReader
  do { reader = try AVAssetReader(asset: asset) } catch { die("cannot read \(path): \(error)") }
  let out = AVAssetReaderTrackOutput(track: info.track, outputSettings: nil)
  out.alwaysCopiesSampleData = false
  reader.add(out)
  guard reader.startReading() else { die("cannot read the samples of \(path)") }
  var all: [Int64] = []
  while let sb = out.copyNextSampleBuffer() {
    guard CMSampleBufferGetNumSamples(sb) > 0 else { continue }
    all.append(ticks(CMSampleBufferGetPresentationTimeStamp(sb), info.timescale, "sample \(all.count)"))
  }
  all.sort()
  for i in 1..<max(all.count, 1) where all[i] == all[i - 1] {
    die("two samples share the presentation time \(all[i])")
  }
  return all
}

/// The frame-hold rule, in integers: the last frame whose time is <= the
/// instant `num / den` seconds (times are ticks of `timescale`).
func heldFrame(_ pts: [Int64], num: Int64, den: Int64, timescale: Int64) -> Int? {
  // pts[j] / timescale <= num / den   <=>   pts[j] * den <= num * timescale
  var lo = 0
  var hi = pts.count - 1
  var best: Int?
  while lo <= hi {
    let mid = (lo + hi) / 2
    if pts[mid] * den <= num * timescale {
      best = mid
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  return best
}

func export(_ path: String, _ args: inout Args) async {
  let segmentsPath = args.req("segments")
  let outDir = args.req("out")
  args.finish()

  let spec = readJSON(segmentsPath)
  guard let fps = spec["fps"] as? Int, fps > 0 else { die("\(segmentsPath): missing fps") }
  guard let segments = spec["segments"] as? [[String: Any]], !segments.isEmpty else {
    die("\(segmentsPath): no segments")
  }

  let asset = AVURLAsset(url: URL(fileURLWithPath: path))
  let info = await loadVideoTrack(asset, path)
  let scale = Int64(info.timescale)
  let pts = presentationTimes(asset, info, path)
  guard !pts.isEmpty else { die("\(path) has no samples") }

  // film frame -> source frame index
  var film: [Int] = []
  for (n, seg) in segments.enumerated() {
    func need(_ key: String) -> Int64 {
      guard let v = seg[key] as? Int else { die("segment \(n): missing integer `\(key)`") }
      return Int64(v)
    }
    switch seg["kind"] as? String {
    case "live":
      let a = need("src_in")
      let b = need("src_out")
      guard b > a else { die("segment \(n): src_out is not after src_in") }
      // (b - a) ticks must be a whole number of film frames.
      guard ((b - a) * Int64(fps)) % scale == 0 else {
        die("segment \(n): \(b - a) ticks is not a whole number of 1/\(fps) s frames")
      }
      let count = (b - a) * Int64(fps) / scale
      for k in 0..<count {
        // instant = a/scale + k/fps = (a*fps + k*scale) / (scale*fps)
        guard
          let j = heldFrame(pts, num: a * Int64(fps) + k * scale, den: scale * Int64(fps), timescale: scale)
        else { die("segment \(n): starts before the first frame of the take") }
        film.append(j)
      }
    case "hold":
      let at = need("src_at")
      let count = need("frames")
      guard count > 0 else { die("segment \(n): a hold needs at least one frame") }
      guard let j = heldFrame(pts, num: at, den: scale, timescale: scale) else {
        die("segment \(n): holds a time before the first frame of the take")
      }
      film.append(contentsOf: [Int](repeating: j, count: Int(count)))
    default:
      die("segment \(n): kind must be `live` or `hold`")
    }
  }

  do {
    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
  } catch { die("cannot create \(outDir): \(error)") }

  let wanted = Set(film)
  var sources: [String: Any] = [:]
  decodeFrames(asset, info, path) { index, t, pb in
    guard t == pts[index] else {
      die("frame \(index): decoded at \(t) but the sample table says \(pts[index])")
    }
    if wanted.contains(index) {
      let name = String(format: "src_%06d.png", index)
      Frame(pb).writePNG("\(outDir)/\(name)")
      sources[String(index)] = ["pts": t, "file": name]
    }
    return index < (wanted.max() ?? 0)
  }
  guard sources.count == wanted.count else {
    die("wrote \(sources.count) source frames, needed \(wanted.count)")
  }

  writeJSON(
    [
      "fps": fps, "timescale": Int(scale), "width": info.width, "height": info.height,
      "film": film, "sources": sources,
    ], to: "\(outDir)/manifest.json")
  print("export: \(film.count) film frames from \(sources.count) source frames -> \(outDir)")
}

@main
enum Conform {
  static func main() async {
    var args = Args(Array(CommandLine.arguments.dropFirst()))
    guard args.words.count == 2 else {
      die("usage: conform scan|diff|export <take> --out ... (see the header of Conform.swift)")
    }
    let path = args.words[1]
    guard FileManager.default.fileExists(atPath: path) else { die("no such file: \(path)") }
    switch args.words[0] {
    case "scan": await scan(path, &args)
    case "diff": await diff(path, &args)
    case "export": await export(path, &args)
    default: die("unknown command `\(args.words[0])`")
    }
  }
}
