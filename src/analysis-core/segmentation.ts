import { pixelBufferToLab } from "./color";
import { ANALYSIS_CONFIG } from "./config";
import { cleanMask, isInCup } from "./mask";
import type { AnalysisInput, SegmentationResult } from "./types";

type Center = [number, number, number];

function distance(lab: Float32Array, pixel: number, center: Center) {
  const index = pixel * 3;
  return Math.hypot(
    lab[index] - center[0],
    lab[index + 1] - center[1],
    lab[index + 2] - center[2],
  );
}

export function segmentFoam(input: AnalysisInput): SegmentationResult {
  const { image, cup } = input;
  const lab = pixelBufferToLab(image);
  const cupPixels: number[] = [];
  let darkestPixel = -1;
  let lightestPixel = -1;
  let darkest = Number.POSITIVE_INFINITY;
  let lightest = Number.NEGATIVE_INFINITY;

  for (let y = 0; y < image.height; y += 1) {
    for (let x = 0; x < image.width; x += 1) {
      if (!isInCup(x, y, cup)) continue;
      const pixel = y * image.width + x;
      cupPixels.push(pixel);
      const lightness = lab[pixel * 3];
      if (lightness < darkest) {
        darkest = lightness;
        darkestPixel = pixel;
      }
      if (lightness > lightest) {
        lightest = lightness;
        lightestPixel = pixel;
      }
    }
  }

  if (!cupPixels.length || darkestPixel < 0 || lightestPixel < 0) {
    return {
      mask: new Uint8Array(image.width * image.height),
      rawMask: new Uint8Array(image.width * image.height),
      lab,
      coverage: 0,
      confidence: 0,
      cupPixelCount: 0,
      clusterSeparation: 0,
    };
  }

  const at = (pixel: number): Center => {
    const i = pixel * 3;
    return [lab[i], lab[i + 1], lab[i + 2]];
  };
  let centers: [Center, Center] = [at(darkestPixel), at(lightestPixel)];

  for (let iteration = 0; iteration < 10; iteration += 1) {
    const sums = [[0, 0, 0, 0], [0, 0, 0, 0]];
    for (const pixel of cupPixels) {
      const cluster = distance(lab, pixel, centers[0]) <= distance(lab, pixel, centers[1]) ? 0 : 1;
      const index = pixel * 3;
      sums[cluster][0] += lab[index];
      sums[cluster][1] += lab[index + 1];
      sums[cluster][2] += lab[index + 2];
      sums[cluster][3] += 1;
    }
    centers = centers.map((center, cluster) => {
      const count = sums[cluster][3];
      return count
        ? [sums[cluster][0] / count, sums[cluster][1] / count, sums[cluster][2] / count]
        : center;
    }) as [Center, Center];
  }

  const foamCluster = centers[0][0] >= centers[1][0] ? 0 : 1;
  const otherCluster = foamCluster === 0 ? 1 : 0;
  const clusterSeparation = Math.hypot(
    centers[0][0] - centers[1][0],
    centers[0][1] - centers[1][1],
    centers[0][2] - centers[1][2],
  );
  const rawMask = new Uint8Array(image.width * image.height);
  let foamCount = 0;

  for (const pixel of cupPixels) {
    const foamDistance = distance(lab, pixel, centers[foamCluster]);
    const cremaDistance = distance(lab, pixel, centers[otherCluster]);
    if (foamDistance - cremaDistance <= input.foamSensitivity) {
      rawMask[pixel] = 1;
      foamCount += 1;
    }
  }

  const minimumSize = Math.max(
    4,
    Math.round(cupPixels.length * ANALYSIS_CONFIG.smallComponentFraction),
  );
  const mask = cleanMask(rawMask, image.width, image.height, minimumSize);
  let cleanedCount = 0;
  for (const pixel of cupPixels) cleanedCount += mask[pixel];
  const coverage = cleanedCount / cupPixels.length;
  const separationConfidence = Math.min(1, Math.max(0, (clusterSeparation - 8) / 24));
  const stabilityPenalty = Math.min(1, Math.abs(cleanedCount - foamCount) / Math.max(1, foamCount));
  const confidence = Math.max(0, separationConfidence * (1 - stabilityPenalty * 0.4));

  return {
    mask,
    rawMask,
    lab,
    coverage,
    confidence,
    cupPixelCount: cupPixels.length,
    clusterSeparation,
  };
}
