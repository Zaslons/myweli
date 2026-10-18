// reel-encode — the composed frames become the marketing Reel.
//
//   reel-encode <frames-dir> --frames 900 --out reel.mp4
//
// Design: docs/design/pro-marketing-reel.md §4.
//
// Compiled with tool/app_store_preview/swift/Common.swift and Writer.swift —
// the App Preview's own movie writer (`writeMovie`), reused, not copied. What
// this file adds is the film's spec, `MovieSpec.social`, and the manifest it
// reads: <frames-dir>/frames.json, one PNG name per film frame in order (a
// held picture repeats its name), with the film's fps, width and height.
// `--frames` is the count the storyboard asks for: a manifest with another
// count is refused, so a short or long render can never become reel.mp4.

import AVFoundation
import Foundation

extension MovieSpec {
  /// Instagram / Facebook Reels, TikTok and WhatsApp Status, from one master:
  /// H.264 High Profile Level 4.1, 1080 x 1920 (9:16), 30 fps constant,
  /// progressive, no frame reordering, a key frame every second, Rec. 709
  /// tags; a stereo AAC-LC 48 kHz track of digital silence — the film has no
  /// sound (the owner adds music inside Instagram), but an MP4 without a
  /// sound track is shown as a GIF by some uploaders (WhatsApp).
  ///
  /// The target is 10 Mbit/s, in the 8–12 the platforms take without a
  /// second look — a target, not the file's rate: half the film's frames
  /// are holds and flat paper, and the encoder spends what the picture
  /// needs (measured 2026-10-18 on the film: 2.77 Mbit/s on average, 8.80
  /// in its busiest second). Padding to a constant rate was measured worse
  /// by the App Preview and is not done. What the master needs instead is a
  /// ceiling on the quantiser, the App Preview's own 10: every key frame as
  /// sharp as the frames after it, and the film's worst decoded frame 54.6
  /// dB from what was composed (48.8 dB at a ceiling of 20, where the hook's
  /// first frame — a key frame of white type on black — went soft). Level
  /// 4.1 allows 62.5 Mbit in any second; verify holds the file to it.
  static let social = MovieSpec(
    container: .mp4, codec: .h264, width: 1080, height: 1920, timescale: 600,
    profileLevel: AVVideoProfileLevelH264High41, averageBitRate: 10_000_000,
    keyFrameInterval: 30, expectedFrameRate: 30, frameReordering: false, maxFrameQP: 10,
    audio: AudioSpec())
}

@main
enum ReelEncode {
  static func main() async {
    var args = Args(Array(CommandLine.arguments.dropFirst()))
    guard args.words.count == 1 else { die("usage: reel-encode <frames-dir> --frames N --out reel.mp4") }
    let dir = args.words[0]
    let outPath = args.req("out")
    let want = args.int("frames")
    args.finish()
    guard outPath.hasSuffix(".mp4") else { die("the output must be a .mp4") }
    // From here a refusal also removes an earlier film of that name.
    unfinished.append(outPath)

    let spec = MovieSpec.social
    let manifest = readJSON("\(dir)/frames.json")
    guard let names = manifest["frames"] as? [String], !names.isEmpty else {
      die("\(dir)/frames.json lists no frames")
    }
    guard manifest["fps"] as? Int == spec.expectedFrameRate,
      manifest["width"] as? Int == spec.width, manifest["height"] as? Int == spec.height
    else {
      die("frames.json is not \(spec.width)x\(spec.height) at \(spec.expectedFrameRate) fps — refusing it")
    }
    guard names.count == want else {
      die("frames.json lists \(names.count) frames, the film is \(want) — refusing it")
    }
    let fps = Int64(spec.expectedFrameRate)
    let step = Int64(spec.timescale) / fps
    guard step * fps == Int64(spec.timescale) else { die("the timescale is not a multiple of the frame rate") }
    let frames = names.enumerated().map { TimedFrame(pts: Int64($0.offset) * step, path: "\(dir)/\($0.element)") }
    await writeMovie(spec, frames: frames, end: Int64(names.count) * step, to: outPath)
    let size = (try? FileManager.default.attributesOfItem(atPath: outPath)[.size] as? Int) ?? 0
    print("reel-encode: \(names.count) frames, \(Double(names.count) / Double(fps)) s, \(size) bytes -> \(outPath)")
  }
}
