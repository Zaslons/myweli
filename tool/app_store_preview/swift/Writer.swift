// One movie writer for the two helpers that write a file:
//   encode    always passes `MovieSpec.appPreview` — the App Store's numbers,
//             with no way to ask for anything else;
//   testclip  passes whatever a test asks for (a take like the recorder's, or a
//             film that is wrong on purpose, for the checker to refuse).

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

struct AudioSpec {
  var formatID: AudioFormatID = kAudioFormatMPEG4AAC  // AAC-LC
  var rate: Int32 = 48_000
  var channels = 2
  var bitRate = 256_000
  /// Tests only: a 440 Hz tone instead of silence.
  var tone = false
  /// Tests only: stop the sound this many ticks into the film.
  var end: Int64?
}

struct MovieSpec {
  var container: AVFileType
  var codec: AVVideoCodecType
  var width: Int
  var height: Int
  var timescale: Int32
  var profileLevel: String
  var averageBitRate: Int
  var keyFrameInterval: Int
  var expectedFrameRate: Int
  var frameReordering: Bool
  var maxFrameQP: Int?
  var audio: AudioSpec?

  /// App Store App Preview, iPhone portrait (Apple's « App preview
  /// specifications », read on 2026-10-13): H.264 High Profile Level 4.0,
  /// 886 x 1920, 30 fps, target 10–12 Mbps, progressive; stereo AAC 256 kbps at
  /// 48 kHz. The sound track is digital silence — the film has no sound and
  /// Apple marks the track as required.
  ///
  /// 11 Mbps is the encoder's target, not the file's rate: a film that is a
  /// still screen most of the time cannot spend it (about 1 Mbps measured).
  /// What the picture needs instead is a ceiling on the quantiser: without
  /// one, each key frame comes out softer than the frames after it (44 dB
  /// against 51 dB measured on a still frame) and still text "breathes" once
  /// a second. With the ceiling every frame measured 54 dB or better. Forcing
  /// a constant 11 Mbps was tried too: it pads the file and measured worse
  /// (41–46 dB), so it is not used.
  static let appPreview = MovieSpec(
    container: .mp4, codec: .h264, width: 886, height: 1920, timescale: 600,
    profileLevel: AVVideoProfileLevelH264High40, averageBitRate: 11_000_000,
    keyFrameInterval: 30, expectedFrameRate: 30, frameReordering: false, maxFrameQP: 10,
    audio: AudioSpec())
}

struct TimedFrame {
  let pts: Int64  // ticks of spec.timescale
  let path: String
}

func channelLayout(_ channels: Int) -> Data {
  var layout = AudioChannelLayout()
  layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
  return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
}

/// `count` sample frames of 16-bit PCM starting at sample `offset`: zeros —
/// digital silence — unless a test asks for a tone.
func pcm(_ spec: AudioSpec, offset: Int64, count: Int) -> CMSampleBuffer {
  var asbd = AudioStreamBasicDescription(
    mSampleRate: Float64(spec.rate), mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
    mBytesPerPacket: UInt32(2 * spec.channels), mFramesPerPacket: 1,
    mBytesPerFrame: UInt32(2 * spec.channels), mChannelsPerFrame: UInt32(spec.channels),
    mBitsPerChannel: 16, mReserved: 0)
  var format: CMAudioFormatDescription?
  let layout = channelLayout(spec.channels)
  let status = layout.withUnsafeBytes { raw in
    CMAudioFormatDescriptionCreate(
      allocator: nil, asbd: &asbd, layoutSize: layout.count,
      layout: raw.bindMemory(to: AudioChannelLayout.self).baseAddress,
      magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
  }
  guard status == noErr, let format else { die("cannot describe the sound (\(status))") }

  var samples = [Int16](repeating: 0, count: count * spec.channels)
  if spec.tone {
    for i in 0..<count {
      let v = Int16(8000 * sin(2 * Double.pi * 440 * Double(offset + Int64(i)) / Double(spec.rate)))
      for c in 0..<spec.channels { samples[i * spec.channels + c] = v }
    }
  }
  let bytes = samples.count * 2
  var block: CMBlockBuffer?
  guard
    CMBlockBufferCreateWithMemoryBlock(
      allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
      customBlockSource: nil, offsetToData: 0, dataLength: bytes,
      flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr, let block,
    samples.withUnsafeBytes({
      CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
    }) == noErr
  else { die("cannot allocate the sound") }
  var sample: CMSampleBuffer?
  guard
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(
      allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
      presentationTimeStamp: CMTime(value: offset, timescale: spec.rate), packetDescriptions: nil,
      sampleBufferOut: &sample) == noErr, let sample
  else { die("cannot build the sound buffer") }
  return sample
}

/// What the two feeding queues need. The video fields are touched by the
/// video queue only and the audio fields by the audio queue only; `failure`
/// is only ever set, and read after both queues are done.
final class Feed: @unchecked Sendable {
  let writer: AVAssetWriter
  let video: AVAssetWriterInput
  let adaptor: AVAssetWriterInputPixelBufferAdaptor
  let pool: CVPixelBufferPool
  let audio: AVAssetWriterInput?
  var nextFrame = 0
  var lastPath = ""
  var buffer: CVPixelBuffer?
  var audioDone: Int64 = 0
  var failure: String?

  init(
    writer: AVAssetWriter, video: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor,
    pool: CVPixelBufferPool, audio: AVAssetWriterInput?
  ) {
    self.writer = writer
    self.video = video
    self.adaptor = adaptor
    self.pool = pool
    self.audio = audio
  }
}

/// Write `frames` (PNG files, each shown from its `pts` to the next one's) to
/// `outPath`. Every PNG must be exactly the spec's size. `end` is where the
/// movie, its tracks and the sound stop. The last frame's own stored duration
/// is another matter: AVFoundation gives it the duration of the frame before
/// it, whatever `end` says (observed here, and in the simulator recorder's
/// files too). At a constant frame rate that is exactly one frame, which is
/// what the film needs; verify.py checks it on the written file.
func writeMovie(_ spec: MovieSpec, frames: [TimedFrame], end: Int64, to outPath: String) async {
  // From here on, stopping for any reason removes the output: no earlier
  // file of that name, and no half-written one, is left to pass for a result.
  unfinished.append(outPath)
  guard !frames.isEmpty else { die("no frames to write") }
  guard frames[0].pts == 0 else { die("the first frame must start at 0, got \(frames[0].pts)") }
  for i in 1..<frames.count where frames[i].pts <= frames[i - 1].pts {
    die("frame \(i) does not come after frame \(i - 1)")
  }
  guard end > frames[frames.count - 1].pts else { die("the end time is not after the last frame") }

  let url = URL(fileURLWithPath: outPath)
  try? FileManager.default.removeItem(at: url)
  let writer: AVAssetWriter
  do { writer = try AVAssetWriter(outputURL: url, fileType: spec.container) } catch {
    die("cannot create \(outPath): \(error.localizedDescription)")
  }
  writer.shouldOptimizeForNetworkUse = true
  writer.movieTimeScale = spec.timescale

  let rec709: [String: Any] = [
    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
  ]
  var compression: [String: Any] = [
    AVVideoAverageBitRateKey: spec.averageBitRate,
    AVVideoMaxKeyFrameIntervalKey: spec.keyFrameInterval,
    AVVideoExpectedSourceFrameRateKey: spec.expectedFrameRate,
    AVVideoAllowFrameReorderingKey: spec.frameReordering,
  ]
  if spec.codec == .h264 { compression[AVVideoProfileLevelKey] = spec.profileLevel }
  if let qp = spec.maxFrameQP {
    compression[kVTCompressionPropertyKey_MaxAllowedFrameQP as String] = qp
  }
  let video = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
      AVVideoCodecKey: spec.codec,
      AVVideoWidthKey: spec.width,
      AVVideoHeightKey: spec.height,
      AVVideoColorPropertiesKey: rec709,
      AVVideoCompressionPropertiesKey: compression,
    ])
  video.expectsMediaDataInRealTime = false
  video.mediaTimeScale = spec.timescale
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: video,
    sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: spec.width,
      kCVPixelBufferHeightKey as String: spec.height,
    ])
  guard writer.canAdd(video) else { die("the writer refuses these video settings") }
  writer.add(video)

  var audio: AVAssetWriterInput?
  if let sound = spec.audio {
    var settings: [String: Any] = [
      AVFormatIDKey: sound.formatID,
      AVSampleRateKey: Int(sound.rate),
      AVNumberOfChannelsKey: sound.channels,
      AVChannelLayoutKey: channelLayout(sound.channels),
    ]
    if sound.formatID == kAudioFormatAppleLossless {
      settings[AVEncoderBitDepthHintKey] = 16  // tests only: lossless has no bit rate
    } else {
      settings[AVEncoderBitRateKey] = sound.bitRate
    }
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    guard writer.canAdd(input) else { die("the writer refuses the audio settings") }
    writer.add(input)
    audio = input
  }

  guard writer.startWriting() else {
    die("cannot start writing \(outPath): \(writer.error?.localizedDescription ?? "unknown")")
  }
  writer.startSession(atSourceTime: .zero)
  guard let pool = adaptor.pixelBufferPool else { die("no pixel buffer pool") }

  let sound = spec.audio ?? AudioSpec()
  let soundEnd = sound.end ?? end
  guard spec.audio == nil || soundEnd * Int64(sound.rate) % Int64(spec.timescale) == 0 else {
    die("the end time is not a whole number of audio samples")
  }
  let totalAudio = soundEnd * Int64(sound.rate) / Int64(spec.timescale)

  // Each input pulls its own data when the writer asks for it; the writer
  // paces the two so the tracks stay interleaved in the file.
  let feed = Feed(writer: writer, video: video, adaptor: adaptor, pool: pool, audio: audio)
  let done = DispatchGroup()
  let timescale = spec.timescale
  let (width, height) = (spec.width, spec.height)

  done.enter()
  video.requestMediaDataWhenReady(on: DispatchQueue(label: "preview.video")) {
    while feed.video.isReadyForMoreMediaData {
      guard feed.nextFrame < frames.count, feed.failure == nil else {
        feed.video.markAsFinished()
        done.leave()
        return
      }
      let frame = frames[feed.nextFrame]
      if frame.path != feed.lastPath {
        let (w, h, bgra) = readPNG(frame.path)
        guard w == width, h == height else {
          die("\(frame.path) is \(w)x\(h), the movie is \(width)x\(height)")
        }
        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, feed.pool, &pb) == kCVReturnSuccess, let pb else {
          die("cannot allocate a pixel buffer")
        }
        CVPixelBufferLockBaseAddress(pb, [])
        let stride = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)!
        bgra.withUnsafeBytes { src in
          for y in 0..<h { memcpy(base + y * stride, src.baseAddress! + y * w * 4, w * 4) }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        // The pixels are sRGB-encoded values carried as Rec. 709 video: tag the
        // buffer so the encoder only applies the 709 matrix, never a transform.
        CVBufferSetAttachment(pb, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pb, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        feed.buffer = pb
        feed.lastPath = frame.path
      }
      if !feed.adaptor.append(feed.buffer!, withPresentationTime: CMTime(value: frame.pts, timescale: timescale)) {
        feed.failure = "cannot append the frame at \(frame.pts): \(feed.writer.error?.localizedDescription ?? "unknown")"
      }
      feed.nextFrame += 1
    }
  }

  if let audio {
    done.enter()
    audio.requestMediaDataWhenReady(on: DispatchQueue(label: "preview.audio")) {
      guard let audio = feed.audio else { return }
      while audio.isReadyForMoreMediaData {
        guard feed.audioDone < totalAudio, feed.failure == nil else {
          audio.markAsFinished()
          done.leave()
          return
        }
        let n = Int(min(Int64(sound.rate), totalAudio - feed.audioDone))
        if !audio.append(pcm(sound, offset: feed.audioDone, count: n)) {
          feed.failure = "cannot append audio: \(feed.writer.error?.localizedDescription ?? "unknown")"
        }
        feed.audioDone += Int64(n)
      }
    }
  }

  await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
    done.notify(queue: .global()) { c.resume() }
  }
  if let failure = feed.failure { die(failure) }

  writer.endSession(atSourceTime: CMTime(value: end, timescale: spec.timescale))
  await writer.finishWriting()
  guard writer.status == .completed else {
    die("writing \(outPath) failed: \(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")")
  }
  // AVAssetWriter moves the index to the front through a scratch copy next to
  // the file (`<name>.sb-…`) and, seen on this Mac, does not always remove it
  // before the process ends. It is ours: remove it.
  let folder = url.deletingLastPathComponent()
  let scratch = url.lastPathComponent + ".sb-"
  for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
  where name.hasPrefix(scratch) {
    try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
  }
  unfinished.removeAll { $0 == outPath }
}
