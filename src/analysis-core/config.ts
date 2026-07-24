export const ANALYSIS_CONFIG = {
  version: 1,
  analysisSize: 512,
  usableCupRadius: 0.95,
  minCoverage: 0.03,
  maxCoverage: 0.65,
  fullScoreCoverageMin: 0.2,
  fullScoreCoverageMax: 0.45,
  zeroCenteringRadius: 0.25,
  minimumConfidence: 0.55,
  smallComponentFraction: 0.0005,
  weights: {
    symmetry: 0.35,
    centering: 0.25,
    coverage: 0.15,
    contrast: 0.15,
    heartShape: 0.1,
  },
} as const;
