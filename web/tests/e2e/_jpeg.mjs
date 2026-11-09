/// What an uploaded JPEG carries, read from its bytes — shared by the stub,
/// which records every PUT to `/r2-upload`, and by the specs, which run the
/// same reader on their own fixtures as the control
/// (docs/design/web-pro-upload-resize.md §8.2).
///
/// `.mjs` because `stub-api.mjs` is plain Node with no build step;
/// `_jpeg.d.mts` gives the specs its types.

/// The fixture's camera make and GPS datum — ASCII the encoder can never write
/// by chance, so finding either in an upload means the metadata survived.
export const MAKE_MARKER = 'MYWELI-E2E-CAM';
export const GPS_MARKER = 'MYWELI-E2E-GPS';

/// Marker segments up to the scan, the frame size, the luminance quantization
/// table (zigzag order) and whether Exif / the fixture's markers are present.
export function inspectJpeg(bytes) {
  const b = Uint8Array.from(bytes);
  const out = {
    jpeg: false,
    width: null,
    height: null,
    segments: [],
    exif: false,
    makeMarker: false,
    gpsMarker: false,
    lumaTable: null,
  };
  const latin1 = Buffer.from(b).toString('latin1');
  out.makeMarker = latin1.includes(MAKE_MARKER);
  out.gpsMarker = latin1.includes(GPS_MARKER);
  if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return out;
  out.jpeg = true;
  let i = 2;
  while (i + 4 <= b.length && b[i] === 0xff) {
    const m = b[i + 1];
    if (m === 0xff) {
      i += 1;
      continue;
    }
    if (m === 0x01 || (m >= 0xd0 && m <= 0xd8)) {
      i += 2;
      continue;
    }
    if (m === 0xd9) break;
    if (m === 0xda) {
      out.segments.push('SOS');
      break;
    }
    const len = (b[i + 2] << 8) | b[i + 3];
    const seg = b.subarray(i + 4, i + 2 + len);
    const head = Buffer.from(seg.subarray(0, 6)).toString('latin1');
    if (m >= 0xe0 && m <= 0xef) {
      out.segments.push(`APP${m - 0xe0}${m === 0xe1 ? `:${head.replace(/\0/g, '')}` : ''}`);
      if (m === 0xe1 && head === 'Exif\0\0') out.exif = true;
    } else if (m === 0xdb) {
      out.segments.push('DQT');
      for (let j = 0; j < seg.length; ) {
        const precision = seg[j] >> 4;
        const id = seg[j] & 0x0f;
        const n = precision ? 128 : 64;
        if (id === 0 && precision === 0 && out.lumaTable === null) {
          out.lumaTable = Array.from(seg.subarray(j + 1, j + 1 + n));
        }
        j += 1 + n;
      }
    } else if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) {
      out.segments.push(`SOF${m - 0xc0}`);
      out.height = (seg[1] << 8) | seg[2];
      out.width = (seg[3] << 8) | seg[4];
    } else {
      out.segments.push(`0x${m.toString(16)}`);
    }
    i += 2 + len;
  }
  return out;
}

/// libjpeg's luminance table for a quality (`jpeg_set_quality`, IJG scaling of
/// Annex K), in zigzag order — what Chromium writes for `quality / 100`.
export function ijgLumaTable(quality) {
  const K = [
    16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69,
    56, 14, 17, 22, 29, 51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81,
    104, 113, 92, 49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
  ];
  const ZIGZAG = [
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27,
    20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58,
    59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
  ];
  const scale = quality < 50 ? Math.floor(5000 / quality) : 200 - quality * 2;
  const natural = K.map((v) => Math.min(255, Math.max(1, Math.floor((v * scale + 50) / 100))));
  return ZIGZAG.map((k) => natural[k]);
}

/// An APP1 Exif segment, big-endian: IFD0 = Make (the marker), Orientation,
/// GPSInfo → a GPS IFD with a position and the GPS marker as map datum.
export function exifApp1({ orientation }) {
  const out = [];
  const u16 = (n) => out.push((n >> 8) & 0xff, n & 0xff);
  const u32 = (n) => out.push((n >>> 24) & 0xff, (n >>> 16) & 0xff, (n >>> 8) & 0xff, n & 0xff);
  const ascii = (s) => out.push(...Buffer.from(`${s}\0`, 'latin1'));
  const entry = (tag, type, count, value) => {
    u16(tag);
    u16(type);
    u32(count);
    u32(value);
  };
  const make = `${MAKE_MARKER}\0`.length; // 15
  const gps = `${GPS_MARKER}\0`.length; // 15
  // Offsets from the TIFF header.
  const ifd0 = 8;
  const makeAt = ifd0 + 2 + 3 * 12 + 4; // 50
  const gpsIfd = makeAt + make + 1; // 66 (word-aligned)
  const latAt = gpsIfd + 2 + 6 * 12 + 4; // 144
  const lonAt = latAt + 24;
  const datumAt = lonAt + 24;
  out.push(0x4d, 0x4d);
  u16(42);
  u32(ifd0);
  u16(3);
  entry(0x010f, 2, make, makeAt);
  out.push(0x01, 0x12, 0x00, 0x03, 0, 0, 0, 1, (orientation >> 8) & 0xff, orientation & 0xff, 0, 0);
  entry(0x8825, 4, 1, gpsIfd);
  u32(0);
  ascii(MAKE_MARKER);
  out.push(0);
  u16(6);
  out.push(0x00, 0x00, 0x00, 0x01, 0, 0, 0, 4, 2, 3, 0, 0); // GPSVersionID 2.3.0.0
  out.push(0x00, 0x01, 0x00, 0x02, 0, 0, 0, 2, 0x4e, 0, 0, 0); // GPSLatitudeRef N
  entry(0x0002, 5, 3, latAt);
  out.push(0x00, 0x03, 0x00, 0x02, 0, 0, 0, 2, 0x57, 0, 0, 0); // GPSLongitudeRef W
  entry(0x0004, 5, 3, lonAt);
  entry(0x0012, 2, gps, datumAt);
  u32(0);
  for (const [n, d] of [[5, 1], [21, 1], [1234, 100], [3, 1], [59, 1], [4321, 100]]) {
    u32(n);
    u32(d);
  }
  ascii(GPS_MARKER);
  const payload = [...Buffer.from('Exif\0\0', 'latin1'), ...out];
  return Buffer.from([0xff, 0xe1, ((payload.length + 2) >> 8) & 0xff, (payload.length + 2) & 0xff, ...payload]);
}

/// `jpeg` with `segment` inserted right after its SOI.
export function spliceAfterSoi(jpeg, segment) {
  const b = Buffer.from(jpeg);
  if (b[0] !== 0xff || b[1] !== 0xd8) throw new Error('not a JPEG');
  return Buffer.concat([b.subarray(0, 2), Buffer.from(segment), b.subarray(2)]);
}

/// A JPEG that is only a header: SOI, a frame of `width` × `height`, EOI. It
/// says « 108 MP » without carrying a pixel — enough for a guard that must
/// answer before decoding.
export function headerOnlyJpeg(width, height) {
  return Buffer.from([
    0xff, 0xd8,
    0xff, 0xc0, 0x00, 0x0b, 0x08, (height >> 8) & 0xff, height & 0xff, (width >> 8) & 0xff, width & 0xff, 0x01, 0x01, 0x11, 0x00,
    0xff, 0xd9,
  ]);
}
