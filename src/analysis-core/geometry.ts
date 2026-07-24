import { deltaE } from "./color";
import { isInCup } from "./mask";
import type { CupCircle } from "./types";

export function maskCentroid(mask: Uint8Array, width: number) {
  let count = 0;
  let sumX = 0;
  let sumY = 0;
  for (let index = 0; index < mask.length; index += 1) {
    if (!mask[index]) continue;
    count += 1;
    sumX += index % width;
    sumY += Math.floor(index / width);
  }
  return count ? { x: sumX / count, y: sumY / count, count } : { x: 0, y: 0, count: 0 };
}

function reflectedIndex(
  x: number,
  y: number,
  centerX: number,
  centerY: number,
  axisX: number,
  axisY: number,
  width: number,
  height: number,
) {
  const dx = x - centerX;
  const dy = y - centerY;
  const projection = dx * axisX + dy * axisY;
  const reflectedX = Math.round(centerX + (2 * projection * axisX - dx));
  const reflectedY = Math.round(centerY + (2 * projection * axisY - dy));
  if (reflectedX < 0 || reflectedX >= width || reflectedY < 0 || reflectedY >= height) return -1;
  return reflectedY * width + reflectedX;
}

export function mirroredOverlap(
  mask: Uint8Array,
  width: number,
  height: number,
  centerX: number,
  centerY: number,
  angleDegrees: number,
) {
  const radians = (angleDegrees * Math.PI) / 180;
  const axisX = Math.sin(radians);
  const axisY = -Math.cos(radians);
  let intersection = 0;
  let union = 0;
  for (let index = 0; index < mask.length; index += 1) {
    const x = index % width;
    const y = Math.floor(index / width);
    const reflected = reflectedIndex(x, y, centerX, centerY, axisX, axisY, width, height);
    const a = mask[index] === 1;
    const b = reflected >= 0 && mask[reflected] === 1;
    if (a || b) union += 1;
    if (a && b) intersection += 1;
  }
  return union ? intersection / union : 0;
}

export function findSymmetryAxis(mask: Uint8Array, width: number, height: number, centerX: number, centerY: number) {
  let bestAngle = 0;
  let bestOverlap = -1;
  for (let angle = 0; angle < 180; angle += 5) {
    const overlap = mirroredOverlap(mask, width, height, centerX, centerY, angle);
    if (overlap > bestOverlap) {
      bestOverlap = overlap;
      bestAngle = angle;
    }
  }
  for (let angle = bestAngle - 4; angle <= bestAngle + 4; angle += 1) {
    const normalized = (angle + 180) % 180;
    const overlap = mirroredOverlap(mask, width, height, centerX, centerY, normalized);
    if (overlap > bestOverlap) {
      bestOverlap = overlap;
      bestAngle = normalized;
    }
  }
  return { angleDegrees: bestAngle, overlap: Math.max(0, bestOverlap) };
}

export function boundaryContrast(mask: Uint8Array, lab: Float32Array, width: number, height: number) {
  let total = 0;
  let samples = 0;
  for (let y = 1; y < height - 1; y += 1) {
    for (let x = 1; x < width - 1; x += 1) {
      const index = y * width + x;
      if (!mask[index]) continue;
      for (const neighbour of [index - 1, index + 1, index - width, index + width]) {
        if (!mask[neighbour]) {
          total += deltaE(lab, index, neighbour);
          samples += 1;
        }
      }
    }
  }
  return samples ? total / samples : 0;
}

export function estimateHeartShape(mask: Uint8Array, width: number, height: number, centroidX: number, centroidY: number) {
  let minX = width;
  let maxX = 0;
  let minY = height;
  let maxY = 0;
  for (let index = 0; index < mask.length; index += 1) {
    if (!mask[index]) continue;
    const x = index % width;
    const y = Math.floor(index / width);
    minX = Math.min(minX, x);
    maxX = Math.max(maxX, x);
    minY = Math.min(minY, y);
    maxY = Math.max(maxY, y);
  }
  if (minX > maxX || minY > maxY) return 0;
  const boxWidth = Math.max(1, maxX - minX + 1);
  const boxHeight = Math.max(1, maxY - minY + 1);
  const upperY = Math.round(minY + boxHeight * 0.18);
  const lowerY = Math.round(minY + boxHeight * 0.86);
  const band = Math.max(1, Math.round(boxHeight * 0.04));
  const occupancy = (centerY: number, fromX: number, toX: number) => {
    let count = 0;
    let possible = 0;
    for (let y = Math.max(0, centerY - band); y <= Math.min(height - 1, centerY + band); y += 1) {
      for (let x = Math.max(0, Math.round(fromX)); x <= Math.min(width - 1, Math.round(toX)); x += 1) {
        possible += 1;
        count += mask[y * width + x];
      }
    }
    return possible ? count / possible : 0;
  };
  const leftLobe = occupancy(upperY, minX, centroidX - boxWidth * 0.08);
  const notch = occupancy(upperY, centroidX - boxWidth * 0.06, centroidX + boxWidth * 0.06);
  const rightLobe = occupancy(upperY, centroidX + boxWidth * 0.08, maxX);
  const point = occupancy(lowerY, centroidX - boxWidth * 0.12, centroidX + boxWidth * 0.12);
  const lowerSides = (
    occupancy(lowerY, minX, centroidX - boxWidth * 0.18) +
    occupancy(lowerY, centroidX + boxWidth * 0.18, maxX)
  ) / 2;
  const lobes = Math.min(1, Math.min(leftLobe, rightLobe) * 1.8);
  const notchScore = Math.min(1, Math.max(0, (Math.max(leftLobe, rightLobe) - notch) * 2.8));
  const taperScore = Math.min(1, Math.max(0, (point - lowerSides) * 2.2 + 0.35));
  const aspect = boxWidth / boxHeight;
  const aspectScore = Math.max(0, 1 - Math.abs(aspect - 1) / 0.8);
  return Math.max(0, Math.min(1, lobes * 0.35 + notchScore * 0.3 + taperScore * 0.25 + aspectScore * 0.1));
}

export function imageQuality(rgba: Uint8ClampedArray, width: number, height: number, cup: CupCircle) {
  let dark = 0;
  let bright = 0;
  let total = 0;
  let laplacianTotal = 0;
  let laplacianSquared = 0;
  for (let y = 1; y < height - 1; y += 2) {
    for (let x = 1; x < width - 1; x += 2) {
      if (!isInCup(x, y, cup)) continue;
      const pixel = y * width + x;
      const luminance = (at: number) => 0.2126 * rgba[at * 4] + 0.7152 * rgba[at * 4 + 1] + 0.0722 * rgba[at * 4 + 2];
      const l = luminance(pixel);
      dark += l < 18 ? 1 : 0;
      bright += l > 245 ? 1 : 0;
      total += 1;
      const laplacian = 4 * l - luminance(pixel - 1) - luminance(pixel + 1) - luminance(pixel - width) - luminance(pixel + width);
      laplacianTotal += laplacian;
      laplacianSquared += laplacian * laplacian;
    }
  }
  const mean = total ? laplacianTotal / total : 0;
  return {
    blurScore: total ? laplacianSquared / total - mean * mean : 0,
    darkFraction: total ? dark / total : 0,
    brightFraction: total ? bright / total : 0,
  };
}
