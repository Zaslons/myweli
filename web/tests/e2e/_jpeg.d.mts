/// Types for `_jpeg.mjs`, the JPEG reader shared by the stub and the specs
/// (`.mjs` because `stub-api.mjs` is plain Node with no build step).

export declare const MAKE_MARKER: string;
export declare const GPS_MARKER: string;

export type JpegInspection = {
  jpeg: boolean;
  width: number | null;
  height: number | null;
  segments: string[];
  exif: boolean;
  makeMarker: boolean;
  gpsMarker: boolean;
  lumaTable: number[] | null;
};

export declare function inspectJpeg(bytes: Uint8Array): JpegInspection;
export declare function ijgLumaTable(quality: number): number[];
export declare function exifApp1(opts: { orientation: number }): Buffer;
export declare function spliceAfterSoi(jpeg: Uint8Array, segment: Uint8Array): Buffer;
export declare function headerOnlyJpeg(width: number, height: number): Buffer;
export declare function orientationTiff(orientation: number, opts?: { type?: number; count?: number }): Buffer;
export declare function orientationApp1(orientation: number, opts?: { type?: number; count?: number }): Buffer;
export declare function spliceAfterFrameHeader(jpeg: Uint8Array, segment: Uint8Array): Buffer;
