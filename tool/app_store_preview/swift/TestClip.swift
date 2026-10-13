// testclip — write a movie that a test describes. Never used to make the film.
//
//   testclip <clip.json> --out file.mov|file.mp4
//
// clip.json:
//   { "width": 1206, "height": 2622, "timescale": 600, "end": 4976,
//     "frames": [ {"pts": 0, "file": "a.png"}, ... ] }
// File names are relative to clip.json. "end" is where the movie and the sound
// stop; the last frame's own stored duration is that of the frame before it
// (see Writer.swift). Everything else is optional:
//   "audio"       false (default) | true | an object with any of
//                 "rate", "channels", "bitrate", "format" ("lc" | "he" | "alac"),
//                 "tone" (true: a 440 Hz tone), "end" (ticks: stop early)
//   "codec"       "h264" (default) | "hevc"
//   "profile"     "high40" (default) | "high" (level chosen by the encoder) |
//                 "high41" | "main41"
//   "bitrate"     bits per second
//   "reordering"  true: let the encoder reorder frames
//
// Two uses: a synthetic take with the recorder's shape (.mov, variable frame
// times, no sound) whose change times are known in advance, and films that are
// wrong on purpose — no sound track, 14.9 s, the wrong size — to watch the
// checker refuse them.

import AVFoundation
import Foundation

@main
enum TestClip {
  static func main() async {
    var args = Args(Array(CommandLine.arguments.dropFirst()))
    guard args.words.count == 1 else { die("usage: testclip <clip.json> --out file") }
    let jsonPath = args.words[0]
    let outPath = args.req("out")
    args.finish()

    let clip = readJSON(jsonPath)
    func int(_ key: String) -> Int {
      guard let v = clip[key] as? Int else { die("\(jsonPath): missing integer `\(key)`") }
      return v
    }
    let profiles = [
      "high": AVVideoProfileLevelH264HighAutoLevel,  // a capture-sized take is past Level 4.0
      "high40": AVVideoProfileLevelH264High40,
      "high41": AVVideoProfileLevelH264High41,
      "main41": AVVideoProfileLevelH264Main41,
    ]
    let profileName = clip["profile"] as? String ?? "high40"
    guard let profile = profiles[profileName] else { die("unknown profile `\(profileName)`") }
    let codecs: [String: AVVideoCodecType] = ["h264": .h264, "hevc": .hevc]
    let codecName = clip["codec"] as? String ?? "h264"
    guard let codec = codecs[codecName] else { die("unknown codec `\(codecName)`") }
    let container: AVFileType
    if outPath.hasSuffix(".mov") {
      container = .mov
    } else if outPath.hasSuffix(".mp4") {
      container = .mp4
    } else {
      die("the output must end in .mov or .mp4")
    }

    var audio: AudioSpec?
    if clip["audio"] as? Bool == true {
      audio = AudioSpec()
    } else if let a = clip["audio"] as? [String: Any] {
      var s = AudioSpec()
      if let v = a["rate"] as? Int { s.rate = Int32(v) }
      if let v = a["channels"] as? Int { s.channels = v }
      if let v = a["bitrate"] as? Int { s.bitRate = v }
      if let v = a["tone"] as? Bool { s.tone = v }
      if let v = a["end"] as? Int { s.end = Int64(v) }
      switch a["format"] as? String ?? "lc" {
      case "lc": break
      case "he": s.formatID = kAudioFormatMPEG4AAC_HE
      case "alac": s.formatID = kAudioFormatAppleLossless
      default: die("unknown audio format")
      }
      audio = s
    }

    let spec = MovieSpec(
      container: container, codec: codec, width: int("width"), height: int("height"),
      timescale: Int32(int("timescale")), profileLevel: profile,
      averageBitRate: clip["bitrate"] as? Int ?? 4_000_000, keyFrameInterval: 30,
      expectedFrameRate: 30, frameReordering: clip["reordering"] as? Bool ?? false,
      maxFrameQP: nil, audio: audio)

    guard let rows = clip["frames"] as? [[String: Any]] else { die("\(jsonPath): missing `frames`") }
    let dir = (jsonPath as NSString).deletingLastPathComponent
    let frames: [TimedFrame] = rows.map { row in
      guard let pts = row["pts"] as? Int, let file = row["file"] as? String else {
        die("\(jsonPath): a frame needs `pts` and `file`")
      }
      return TimedFrame(pts: Int64(pts), path: "\(dir)/\(file)")
    }
    await writeMovie(spec, frames: frames, end: Int64(int("end")), to: outPath)
    print("testclip: \(frames.count) frames -> \(outPath)")
  }
}
