// encode — the composed frames become the App Preview file.
//
//   encode <frames-dir> --out preview.mp4
//
// <frames-dir>/frames.json is compose's manifest: one PNG name per film
// frame, in order (a held picture repeats its name). There is nothing to
// configure: the file is written to `MovieSpec.appPreview` or not at all.
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
    await writeMovie(spec, frames: frames, end: Int64(names.count) * step, to: outPath)

    let size = (try? FileManager.default.attributesOfItem(atPath: outPath)[.size] as? Int) ?? 0
    print("encode: \(names.count) frames, \(Double(names.count) / Double(fps)) s, \(size) bytes -> \(outPath)")
  }
}
