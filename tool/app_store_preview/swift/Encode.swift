// encode — the composed frames become the App Preview file.
//
//   encode <frames-dir> --out preview.mp4
//
// <frames-dir>/frames.json is compose's manifest: one PNG name per film
// frame, in order (a held picture repeats its name). There is nothing to
// configure: the file is written to `MovieSpec.appPreview` or not at all —
// with one measured exception: a file whose busiest second is over Level
// 4.0's 25 Mbit is written again with a higher quantiser ceiling, and the
// output says so (`levelPeakBits`, below).
// `avconvert` is not used because its presets have fixed sizes; `ffmpeg` is
// not installed.

import AVFoundation
import Foundation

@main
enum Encode {
  static func main() async {
    var args = Args(Array(CommandLine.arguments.dropFirst()))
    guard args.words.count == 1 else { die("usage: encode <frames-dir> --out preview.mp4") }
    let dir = args.words[0]
    let outPath = args.req("out")
    args.finish()
    guard outPath.hasSuffix(".mp4") else { die("the output must be a .mp4") }
    // A refusal below also removes an earlier film of that name: after a
    // failed build there is no preview.mp4 to mistake for this run's.
    unfinished.append(outPath)

    let spec = MovieSpec.appPreview
    let manifest = readJSON("\(dir)/frames.json")
    guard let names = manifest["frames"] as? [String], !names.isEmpty else {
      die("\(dir)/frames.json lists no frames")
    }
    guard manifest["fps"] as? Int == spec.expectedFrameRate,
      manifest["width"] as? Int == spec.width, manifest["height"] as? Int == spec.height
    else {
      die("frames.json is not \(spec.width)x\(spec.height) at \(spec.expectedFrameRate) fps — refusing it")
    }
    let fps = Int64(spec.expectedFrameRate)
    guard names.count >= 15 * Int(fps), names.count <= 30 * Int(fps) else {
      die("\(names.count) frames is \(Double(names.count) / Double(fps)) s; a preview is 15 to 30 s")
    }

    let step = Int64(spec.timescale) / fps
    guard step * fps == Int64(spec.timescale) else { die("the timescale is not a multiple of the frame rate") }
    let frames = names.enumerated().map { TimedFrame(pts: Int64($0.offset) * step, path: "\(dir)/\($0.element)") }
    // Written at the spec's quantiser ceiling; measured; written again with
    // the ceiling raised a step at a time while its busiest second is over
    // what the level allows (`levelPeakBits`, below).
    var written = spec
    var peak = (bits: 0, first: 0)
    for ceiling in qpCeilings(from: spec.maxFrameQP ?? qpCeilingLast) {
      written.maxFrameQP = ceiling
      await writeMovie(written, frames: frames, end: Int64(names.count) * step, to: outPath)
      // written whole, but not yet accepted: a refusal below removes it
      unfinished += [outPath]
      peak = await busiestSecond(outPath, frames: Int(fps))
      let seen = "QP ceiling \(ceiling): busiest second \(mbit(peak.bits)) Mbit (frames \(peak.first)–\(peak.first + Int(fps) - 1))"
      if peak.bits <= levelPeakBits {
        unfinished.removeAll { $0 == outPath }
        print("encode: \(seen), within Level 4.0's \(mbit(levelPeakBits))")
        break
      }
      guard ceiling < qpCeilingLast else {
        die("\(seen): over Level 4.0's \(mbit(levelPeakBits)) Mbit even at the last ceiling — the picture is too busy for the App Preview's level")
      }
      print("encode: \(seen), over Level 4.0's \(mbit(levelPeakBits)) — written again")
    }

    let size = (try? FileManager.default.attributesOfItem(atPath: outPath)[.size] as? Int) ?? 0
    print("encode: \(names.count) frames, \(Double(names.count) / Double(fps)) s, \(size) bytes -> \(outPath)")
  }
}

/// High Profile Level 4.0 allows 25 Mbit a second (MaxBR 20 000 × 1.25
/// kbit/s, H.264 Table A-1, A.3.3); verify.py holds the written file to it as
/// the bits of its busiest 30 consecutive frames. `MovieSpec.appPreview`'s
/// quantiser ceiling keeps still text sharp, and on most films costs nothing
/// (the rehearsal cut of 2026-10-13: 7.2 Mbit in its busiest second). On a
/// second that is all new detail it spends more than the level allows:
/// measured on the film of scenes of 2026-10-14, S6's cover photograph
/// scrolling, 25.31 Mbit at the ceiling of 10. So the written file is
/// measured, and over the limit it is written again with the ceiling two
/// steps higher — the least loss of sharpness that fits — up to
/// `qpCeilingLast`, past which the encode is refused rather than written.
let levelPeakBits = 25_000_000
let qpCeilingLast = 20

func qpCeilings(from first: Int) -> [Int] {
  first >= qpCeilingLast ? [first] : Array(stride(from: first, through: qpCeilingLast, by: 2))
}

func mbit(_ bits: Int) -> String { String(format: "%.2f", Double(bits) / 1_000_000) }

/// The bits of the busiest `frames` consecutive video samples of a written
/// file, and the first of them — what verify.py measures, read here through
/// AVFoundation from the samples as stored.
func busiestSecond(_ path: String, frames: Int) async -> (bits: Int, first: Int) {
  let asset = AVURLAsset(url: URL(fileURLWithPath: path))
  let info = await loadVideoTrack(asset, path)
  var sizes: [Int] = []
  do {
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: info.track, outputSettings: nil)
    output.alwaysCopiesSampleData = false
    reader.add(output)
    guard reader.startReading() else { die("cannot read the samples of \(path)") }
    while let sb = output.copyNextSampleBuffer() {
      guard CMSampleBufferGetNumSamples(sb) > 0 else { continue }
      sizes.append(CMSampleBufferGetTotalSampleSize(sb))
    }
  } catch { die("cannot read the samples of \(path): \(error.localizedDescription)") }
  var best = (bits: 0, first: 0)
  var window = 0
  for i in sizes.indices {
    window += sizes[i]
    if i >= frames { window -= sizes[i - frames] }
    if window * 8 > best.bits { best = (window * 8, max(0, i - frames + 1)) }
  }
  return best
}
