import { ANALYSIS_CONFIG } from "./config";
import {
  boundaryContrast,
  estimateHeartShape,
  findSymmetryAxis,
  imageQuality,
  maskCentroid,
} from "./geometry";
import { outlinePoints } from "./mask";
import { segmentFoam } from "./segmentation";
import type {
  AnalysisInput,
  AnalysisResult,
  CoachingTip,
  ComponentScores,
  LatteMetrics,
} from "./types";

const clamp01 = (value: number) => Math.max(0, Math.min(1, value));
const score = (value: number) => Math.round(clamp01(value) * 100);

export function coverageScore(coverage: number) {
  const { fullScoreCoverageMin: min, fullScoreCoverageMax: max } = ANALYSIS_CONFIG;
  if (coverage >= min && coverage <= max) return 100;
  if (coverage < min) return score(coverage / min);
  return score((ANALYSIS_CONFIG.maxCoverage - coverage) / (ANALYSIS_CONFIG.maxCoverage - max));
}

export function weightedScore(scores: ComponentScores) {
  const weights = ANALYSIS_CONFIG.weights;
  return Math.round(
    scores.symmetry * weights.symmetry +
      scores.centering * weights.centering +
      scores.coverage * weights.coverage +
      scores.contrast * weights.contrast +
      scores.heartShape * weights.heartShape,
  );
}

export function buildTips(metrics: LatteMetrics, scores: ComponentScores): CoachingTip[] {
  const candidates: Array<{ value: number; tip: CoachingTip }> = [
    {
      value: scores.symmetry,
      tip: {
        metric: "symmetry",
        title: "Focus on symmetry",
        observation: `The mirrored halves overlap by ${Math.round(metrics.symmetry * 100)}%.`,
        suggestion: "Keep the pitcher moving along the detected centerline during the draw and finishing stroke.",
      },
    },
    {
      value: scores.centering,
      tip: {
        metric: "centering",
        title: "Bring the design toward center",
        observation: `The pattern sits ${Math.round(metrics.centeringOffset.radial * 100)}% of the cup radius from center.`,
        suggestion: "Use the cup center as your target when the white pattern begins to form.",
      },
    },
    {
      value: scores.coverage,
      tip: {
        metric: "coverage",
        title: metrics.coverage < ANALYSIS_CONFIG.fullScoreCoverageMin ? "Build a fuller canvas" : "Leave a little more breathing room",
        observation: `The white design covers ${Math.round(metrics.coverage * 100)}% of the usable cup.`,
        suggestion: metrics.coverage < ANALYSIS_CONFIG.fullScoreCoverageMin
          ? "Aim for a slightly larger, more deliberate white shape on your next pour."
          : "Keep the design comfortably inside the rim so its silhouette stays readable.",
      },
    },
    {
      value: scores.contrast,
      tip: {
        metric: "contrast",
        title: "Strengthen the outline",
        observation: "The white-to-brown boundary is softer than the other measured qualities.",
        suggestion: "Aim for a clean transition between the white design and the surrounding crema.",
      },
    },
    {
      value: scores.heartShape,
      tip: {
        metric: "heartShape",
        title: "Clarify the heart silhouette",
        observation: "The notch, paired lobes, or lower point are not yet strongly defined.",
        suggestion: "Prioritize two even lobes and a centered finishing line that creates a distinct point.",
      },
    },
  ];
  return candidates.sort((a, b) => a.value - b.value).slice(0, 2).map((entry) => entry.tip);
}

export function analyzeLatteArt(input: AnalysisInput): AnalysisResult {
  const segmentation = segmentFoam(input);
  const { image, cup } = input;
  const centroid = maskCentroid(segmentation.mask, image.width);
  const axis = findSymmetryAxis(segmentation.mask, image.width, image.height, centroid.x, centroid.y);
  const contrast = boundaryContrast(segmentation.mask, segmentation.lab, image.width, image.height);
  const heartShape = estimateHeartShape(segmentation.mask, image.width, image.height, centroid.x, centroid.y);
  const centerX = (centroid.x - cup.centerX) / cup.radius;
  const centerY = (centroid.y - cup.centerY) / cup.radius;
  const radial = Math.hypot(centerX, centerY);
  const quality = imageQuality(image.rgba, image.width, image.height, cup);
  const metrics: LatteMetrics = {
    centeringOffset: { x: centerX, y: centerY, radial },
    symmetry: axis.overlap,
    coverage: segmentation.coverage,
    contrast,
    heartShape,
    segmentationConfidence: segmentation.confidence,
  };
  const componentScores: ComponentScores = {
    symmetry: score(axis.overlap),
    centering: score(1 - radial / ANALYSIS_CONFIG.zeroCenteringRadius),
    coverage: coverageScore(segmentation.coverage),
    contrast: score((contrast - 4) / 28),
    heartShape: score(heartShape),
  };
  const warnings: string[] = [];
  if (quality.blurScore < 35) warnings.push("The photo may be soft or out of focus; fine edges could be understated.");
  if (quality.darkFraction > 0.18) warnings.push("A large part of the cup is very dark; try more even lighting next time.");
  if (quality.brightFraction > 0.18) warnings.push("Bright reflections may be included in the foam mask.");
  if (segmentation.coverage < ANALYSIS_CONFIG.minCoverage) warnings.push("Too little foam was detected. Increase sensitivity or adjust the cup circle.");
  if (segmentation.coverage > ANALYSIS_CONFIG.maxCoverage) warnings.push("Too much of the cup was detected as foam. Decrease sensitivity or adjust the cup circle.");
  if (segmentation.confidence < ANALYSIS_CONFIG.minimumConfidence) warnings.push("Foam and crema are not separated clearly enough for a reliable score.");
  const scoreAllowed =
    segmentation.coverage >= ANALYSIS_CONFIG.minCoverage &&
    segmentation.coverage <= ANALYSIS_CONFIG.maxCoverage &&
    segmentation.confidence >= ANALYSIS_CONFIG.minimumConfidence;
  const tips = scoreAllowed ? buildTips(metrics, componentScores) : [];
  const weakest = tips[0];
  return {
    metrics,
    componentScores,
    overallScore: scoreAllowed ? weightedScore(componentScores) : null,
    tips,
    annotations: [
      { type: "cup", circle: cup },
      { type: "centroid", x: centroid.x, y: centroid.y },
      { type: "axis", angleDegrees: axis.angleDegrees, centerX: centroid.x, centerY: centroid.y },
      { type: "outline", points: outlinePoints(segmentation.mask, image.width, image.height) },
      ...(weakest ? [{ type: "problem" as const, x: centroid.x, y: centroid.y, label: weakest.title }] : []),
    ],
    warnings,
    mask: segmentation.mask,
    quality,
    axisAngleDegrees: axis.angleDegrees,
  };
}
