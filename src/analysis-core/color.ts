import type { PixelBuffer } from "./types";

function srgbToLinear(value: number) {
  const channel = value / 255;
  return channel <= 0.04045
    ? channel / 12.92
    : Math.pow((channel + 0.055) / 1.055, 2.4);
}

function pivotLab(value: number) {
  const delta = 6 / 29;
  return value > delta ** 3
    ? Math.cbrt(value)
    : value / (3 * delta ** 2) + 4 / 29;
}

export function rgbToLab(r: number, g: number, b: number) {
  const lr = srgbToLinear(r);
  const lg = srgbToLinear(g);
  const lb = srgbToLinear(b);
  const x = (0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb) / 0.95047;
  const y = 0.2126729 * lr + 0.7151522 * lg + 0.072175 * lb;
  const z = (0.0193339 * lr + 0.119192 * lg + 0.9503041 * lb) / 1.08883;
  const fx = pivotLab(x);
  const fy = pivotLab(y);
  const fz = pivotLab(z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)] as const;
}

export function pixelBufferToLab(image: PixelBuffer) {
  const lab = new Float32Array(image.width * image.height * 3);
  for (let pixel = 0; pixel < image.width * image.height; pixel += 1) {
    const rgbaIndex = pixel * 4;
    const labIndex = pixel * 3;
    const converted = rgbToLab(
      image.rgba[rgbaIndex],
      image.rgba[rgbaIndex + 1],
      image.rgba[rgbaIndex + 2],
    );
    lab[labIndex] = converted[0];
    lab[labIndex + 1] = converted[1];
    lab[labIndex + 2] = converted[2];
  }
  return lab;
}

export function deltaE(lab: Float32Array, firstPixel: number, secondPixel: number) {
  const a = firstPixel * 3;
  const b = secondPixel * 3;
  return Math.hypot(
    lab[a] - lab[b],
    lab[a + 1] - lab[b + 1],
    lab[a + 2] - lab[b + 2],
  );
}
