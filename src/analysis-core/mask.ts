import { ANALYSIS_CONFIG } from "./config";
import type { CupCircle } from "./types";

export function isInCup(x: number, y: number, cup: CupCircle, scale = ANALYSIS_CONFIG.usableCupRadius) {
  return Math.hypot(x - cup.centerX, y - cup.centerY) <= cup.radius * scale;
}

function erode(mask: Uint8Array, width: number, height: number) {
  const output = new Uint8Array(mask.length);
  for (let y = 1; y < height - 1; y += 1) {
    for (let x = 1; x < width - 1; x += 1) {
      const index = y * width + x;
      let keep = 1;
      for (let dy = -1; dy <= 1 && keep; dy += 1) {
        for (let dx = -1; dx <= 1; dx += 1) {
          if (!mask[index + dy * width + dx]) {
            keep = 0;
            break;
          }
        }
      }
      output[index] = keep;
    }
  }
  return output;
}

function dilate(mask: Uint8Array, width: number, height: number) {
  const output = new Uint8Array(mask.length);
  for (let y = 1; y < height - 1; y += 1) {
    for (let x = 1; x < width - 1; x += 1) {
      const index = y * width + x;
      let fill = 0;
      for (let dy = -1; dy <= 1 && !fill; dy += 1) {
        for (let dx = -1; dx <= 1; dx += 1) {
          if (mask[index + dy * width + dx]) {
            fill = 1;
            break;
          }
        }
      }
      output[index] = fill;
    }
  }
  return output;
}

export function cleanMask(mask: Uint8Array, width: number, height: number, minimumSize: number) {
  let cleaned = dilate(erode(mask, width, height), width, height);
  cleaned = erode(dilate(cleaned, width, height), width, height);
  const visited = new Uint8Array(cleaned.length);
  const output = cleaned.slice();
  const queue = new Int32Array(cleaned.length);
  for (let start = 0; start < cleaned.length; start += 1) {
    if (!cleaned[start] || visited[start]) continue;
    let head = 0;
    let tail = 1;
    queue[0] = start;
    visited[start] = 1;
    while (head < tail) {
      const current = queue[head++];
      const x = current % width;
      const neighbours = [current - width, current + width, current - 1, current + 1];
      for (const next of neighbours) {
        if (next < 0 || next >= cleaned.length || visited[next] || !cleaned[next]) continue;
        if ((next === current - 1 && x === 0) || (next === current + 1 && x === width - 1)) continue;
        visited[next] = 1;
        queue[tail++] = next;
      }
    }
    if (tail < minimumSize) {
      for (let i = 0; i < tail; i += 1) output[queue[i]] = 0;
    }
  }
  return output;
}

export function outlinePoints(mask: Uint8Array, width: number, height: number, maximum = 500) {
  const boundary: Array<{ x: number; y: number }> = [];
  for (let y = 1; y < height - 1; y += 1) {
    for (let x = 1; x < width - 1; x += 1) {
      const index = y * width + x;
      if (!mask[index]) continue;
      if (!mask[index - 1] || !mask[index + 1] || !mask[index - width] || !mask[index + width]) {
        boundary.push({ x, y });
      }
    }
  }
  if (boundary.length <= maximum) return boundary;
  const stride = boundary.length / maximum;
  return Array.from({ length: maximum }, (_, i) => boundary[Math.floor(i * stride)]);
}
