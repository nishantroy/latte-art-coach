export type PixelBuffer = {
  width: number;
  height: number;
  rgba: Uint8ClampedArray;
};

export type CupCircle = {
  centerX: number;
  centerY: number;
  radius: number;
};

export type AnalysisInput = {
  image: PixelBuffer;
  cup: CupCircle;
  pattern: "heart";
  foamSensitivity: number;
};

export type CenteringOffset = { x: number; y: number; radial: number };

export type LatteMetrics = {
  centeringOffset: CenteringOffset;
  symmetry: number;
  coverage: number;
  contrast: number;
  heartShape: number;
  segmentationConfidence: number;
};

export type ComponentScores = {
  symmetry: number;
  centering: number;
  coverage: number;
  contrast: number;
  heartShape: number;
};

export type CoachingTip = {
  metric: keyof ComponentScores;
  title: string;
  observation: string;
  suggestion: string;
};

export type Annotation =
  | { type: "cup"; circle: CupCircle }
  | { type: "centroid"; x: number; y: number }
  | { type: "axis"; angleDegrees: number; centerX: number; centerY: number }
  | { type: "outline"; points: Array<{ x: number; y: number }> }
  | { type: "problem"; x: number; y: number; label: string };

export type ImageQuality = {
  blurScore: number;
  darkFraction: number;
  brightFraction: number;
};

export type SegmentationResult = {
  mask: Uint8Array;
  rawMask: Uint8Array;
  lab: Float32Array;
  coverage: number;
  confidence: number;
  cupPixelCount: number;
  clusterSeparation: number;
};

export type AnalysisResult = {
  metrics: LatteMetrics;
  componentScores: ComponentScores;
  overallScore: number | null;
  tips: CoachingTip[];
  annotations: Annotation[];
  warnings: string[];
  mask: Uint8Array;
  quality: ImageQuality;
  axisAngleDegrees: number;
};
