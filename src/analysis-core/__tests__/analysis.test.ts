import { describe, expect, it } from "vitest";
import {
  analyzeLatteArt,
  buildTips,
  cleanMask,
  coverageScore,
  findSymmetryAxis,
  maskCentroid,
  mirroredOverlap,
  rgbToLab,
  segmentFoam,
  weightedScore,
  type AnalysisInput,
  type ComponentScores,
  type PixelBuffer,
} from "..";

function syntheticHeart(options: { shiftX?: number; rightCut?: boolean; foam?: [number, number, number] } = {}) {
  const size = 128;
  const rgba = new Uint8ClampedArray(size * size * 4);
  const foam = options.foam ?? [238, 229, 211];
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const i = (y * size + x) * 4;
      rgba[i] = 86;
      rgba[i + 1] = 43;
      rgba[i + 2] = 25;
      rgba[i + 3] = 255;
      const nx = (x - 64 - (options.shiftX ?? 0)) / 29;
      const ny = -(y - 64) / 29;
      const heart = (nx * nx + ny * ny - 1) ** 3 - nx * nx * ny ** 3 <= 0;
      const cut = options.rightCut && x > 70 && y < 67;
      if (heart && !cut) {
        rgba[i] = foam[0];
        rgba[i + 1] = foam[1];
        rgba[i + 2] = foam[2];
      }
    }
  }
  return { width: size, height: size, rgba } satisfies PixelBuffer;
}

const input = (image = syntheticHeart(), sensitivity = 0): AnalysisInput => ({
  image,
  cup: { centerX: 64, centerY: 64, radius: 58 },
  pattern: "heart",
  foamSensitivity: sensitivity,
});

describe("color conversion", () => {
  it("maps white and black to Lab lightness endpoints", () => {
    expect(rgbToLab(255, 255, 255)[0]).toBeCloseTo(100, 4);
    expect(rgbToLab(0, 0, 0)[0]).toBeCloseTo(0, 4);
  });
});

describe("mask utilities", () => {
  it("removes isolated components and retains the main region", () => {
    const mask = new Uint8Array(100);
    for (let y = 3; y <= 7; y += 1) for (let x = 3; x <= 7; x += 1) mask[y * 10 + x] = 1;
    mask[1] = 1;
    const cleaned = cleanMask(mask, 10, 10, 5);
    expect(cleaned[1]).toBe(0);
    expect(cleaned[5 * 10 + 5]).toBe(1);
  });

  it("finds a centered centroid", () => {
    const mask = new Uint8Array(25);
    mask[2 * 5 + 1] = 1;
    mask[2 * 5 + 3] = 1;
    expect(maskCentroid(mask, 5)).toMatchObject({ x: 2, y: 2, count: 2 });
  });
});

describe("segmentation", () => {
  it("is deterministic and leaves all pixels outside the cup empty", () => {
    const first = segmentFoam(input());
    const second = segmentFoam(input());
    expect(first.mask).toEqual(second.mask);
    expect(first.confidence).toBeGreaterThan(0.55);
    expect(first.mask[0]).toBe(0);
  });

  it("changes detected coverage predictably with sensitivity", () => {
    const strict = segmentFoam(input(syntheticHeart(), -15));
    const permissive = segmentFoam(input(syntheticHeart(), 15));
    expect(permissive.coverage).toBeGreaterThanOrEqual(strict.coverage);
  });
});

describe("geometry and scoring", () => {
  it("scores a symmetric mask higher than an asymmetric version", () => {
    const symmetric = segmentFoam(input()).mask;
    const asymmetric = segmentFoam(input(syntheticHeart({ rightCut: true }))).mask;
    const center = maskCentroid(symmetric, 128);
    const centerAsymmetric = maskCentroid(asymmetric, 128);
    const a = findSymmetryAxis(symmetric, 128, 128, center.x, center.y);
    const b = findSymmetryAxis(asymmetric, 128, 128, centerAsymmetric.x, centerAsymmetric.y);
    expect(a.overlap).toBeGreaterThan(b.overlap);
    expect(mirroredOverlap(symmetric, 128, 128, center.x, center.y, a.angleDegrees)).toBeCloseTo(a.overlap, 6);
  });

  it("uses the documented score weights exactly", () => {
    const scores: ComponentScores = { symmetry: 90, centering: 80, coverage: 70, contrast: 60, heartShape: 50 };
    expect(weightedScore(scores)).toBe(Math.round(90 * 0.35 + 80 * 0.25 + 70 * 0.15 + 60 * 0.15 + 50 * 0.1));
    expect(coverageScore(0.25)).toBe(100);
    expect(coverageScore(0)).toBe(0);
  });

  it("penalizes an off-center design", () => {
    const centered = analyzeLatteArt(input());
    const shifted = analyzeLatteArt(input(syntheticHeart({ shiftX: 14 })));
    expect(centered.componentScores.centering).toBeGreaterThan(shifted.componentScores.centering);
  });
});

describe("analysis result", () => {
  it("returns no more than two deterministic coaching tips", () => {
    const result = analyzeLatteArt(input());
    expect(result.tips.length).toBeLessThanOrEqual(2);
    expect(result.annotations.some((annotation) => annotation.type === "axis")).toBe(true);
    expect(result.annotations.some((annotation) => annotation.type === "outline")).toBe(true);
  });

  it("suppresses scores for an unsegmentable image", () => {
    const flat = syntheticHeart({ foam: [86, 43, 25] });
    const result = analyzeLatteArt(input(flat));
    expect(result.overallScore).toBeNull();
    expect(result.tips).toEqual([]);
    expect(result.warnings.length).toBeGreaterThan(0);
  });

  it("orders feedback by the lowest component score", () => {
    const metrics = analyzeLatteArt(input()).metrics;
    const scores: ComponentScores = { symmetry: 80, centering: 5, coverage: 30, contrast: 90, heartShape: 70 };
    const tips = buildTips(metrics, scores);
    expect(tips[0].metric).toBe("centering");
    expect(tips[1].metric).toBe("coverage");
  });
});
