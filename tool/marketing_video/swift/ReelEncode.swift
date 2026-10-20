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
  /// second look — a target, not the file's rate: the encoder spends what
  /// the picture needs. What the master needs is a ceiling on the
  /// quantiser: every key frame as sharp as the frames after it. The first
  /// cut (graphics and screen captures only) used the App Preview's own 10
  /// (2.74 Mbit/s on average, the worst key frame 54.5 dB). Amendment A1
  /// brought two photographs that push in on every frame, and at 10 their
  /// grain cost 11.56 Mbit/s on average and 65.0 Mbit in the busiest second
  /// — over Level 4.1's 62.5. Measured on the A1 film (2026-10-18), ceiling
  /// against average / busiest second / worst of 46 decoded frames: 11 —
  /// 10.11 / 56.8 / 48.0 dB; 12 — 9.36 / 52.0 / 47.8; 14 — 7.08 / 39.2 /
  /// 47.0; 16 — 5.40 / 31.6 / 45.5. 12 keeps the file inside Level 4.1 with
  /// room and every graphic frame sampled at 52 dB or better; a photograph's grain is the only
  /// thing under 48 dB (1.1 grey levels root mean square at 47.8), and
  /// verify holds the pictures to 47.
  static let social = MovieSpec(
    container: .mp4, codec: .h264, width: 1080, height: 1920, timescale: 600,
    profileLevel: AVVideoProfileLevelH264High41, averageBitRate: 10_000_000,
    keyFrameInterval: 30, expectedFrameRate: 30, frameReordering: false, maxFrameQP: 12,
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
