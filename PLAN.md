# Latte Art Coach — Web MVP Plan

## Summary

Build a local-only Expo Router web app that analyzes uploaded photographs of heart-shaped latte art. The MVP supports a system file picker, manual cup alignment, adjustable foam segmentation, annotated metrics, two prioritized coaching tips, and a transparent 0–100 visual score.

This file is the canonical implementation plan. Subsequent scope or architecture changes must update it. Uploaded images remain in memory and are discarded on refresh.

## Implementation

### App foundation and user flow

- Create an Expo Router TypeScript project targeting web first while preserving iOS/Android compatibility.
- Implement a single-page state machine: `upload → align → analyze → results`.
- Use `expo-image-picker` for JPEG, PNG, and WebP selection; reject unsupported formats such as HEIC with a clear message.
- Enforce a 20 MB limit and a minimum 640 px shortest dimension.
- Decode and resize images to a 512×512 analysis buffer while retaining a display-resolution preview.
- Keep the selected image, mask, and result only in React memory; restarting or refreshing resets the session.

### Cup alignment and segmentation

- Initialize an adjustable circle at the image center with a radius equal to 42% of the shortest image dimension.
- Let the user drag the circle and resize it with one handle; only pixels inside 95% of its radius participate in analysis.
- Normalize the cup crop and convert pixels from sRGB to Lab color space.
- Segment white foam using two-cluster Lab k-means within the cup mask, assigning the lighter cluster as foam.
- Provide a sensitivity slider from `-20` to `+20` that shifts the cluster decision boundary and updates the visible mask.
- Clean the mask with a one-pixel morphological open/close and remove connected regions smaller than 0.05% of the cup area.
- Show the foam mask as a translucent overlay before analysis so the user can correct the circle or sensitivity.
- Warn, but do not block, on blur or poor exposure. Block scoring when decoding fails, the mask covers less than 3% or more than 65% of the cup, or segmentation confidence is below `0.55`.

### Analysis engine and interfaces

Keep image decoding platform-specific and all measurement logic in a pure TypeScript `analysis-core` module:

```ts
type PixelBuffer = {
  width: number;
  height: number;
  rgba: Uint8ClampedArray;
};

type CupCircle = {
  centerX: number;
  centerY: number;
  radius: number;
};

type AnalysisInput = {
  image: PixelBuffer;
  cup: CupCircle;
  pattern: "heart";
  foamSensitivity: number;
};

type LatteMetrics = {
  centeringOffset: { x: number; y: number; radial: number };
  symmetry: number;
  coverage: number;
  contrast: number;
  heartShape: number;
  segmentationConfidence: number;
};

type AnalysisResult = {
  metrics: LatteMetrics;
  componentScores: {
    symmetry: number;
    centering: number;
    coverage: number;
    contrast: number;
    heartShape: number;
  };
  overallScore: number | null;
  tips: CoachingTip[];
  annotations: Annotation[];
  warnings: string[];
};
```

- Determine the heart’s natural vertical axis by testing mirrored-mask overlap across candidate angles and selecting the highest-overlap axis.
- Calculate centering, symmetry, coverage, boundary contrast, and heart shape.
- Produce a transparent score weighted as symmetry 35%, centering 25%, coverage 15%, contrast 15%, and heart shape 10%.
- Normalize components to 0–100 using configurable thresholds. Treat 20–45% coverage as the full-score range and an offset at or beyond 25% of the cup radius as zero centering points.
- Label the result “Visual analysis score,” never “latte quality” or “skill score.”
- Return no overall score when confidence is insufficient.

### Results and coaching

- Overlay the cup boundary, cup center, pattern centroid, detected symmetry axis, foam outline, and highlighted problem region on the original photo.
- Display the overall score, five component scores, confidence, and relevant warnings.
- Generate coaching from deterministic rules and show at most two tips, ordered by the lowest reliable component score.
- Keep observations separate from possible remedies and never infer an exact unobservable cause from a still photograph.
- Include “Analyze another photo,” which clears the in-memory session.

## Test Plan

- Unit-test color conversion, k-means determinism, morphology, connected components, centroid, mirrored overlap, score weighting, and feedback ordering using synthetic pixel buffers.
- Test centered, shifted, rotated, asymmetric, small, oversized, low-contrast, and malformed synthetic heart masks with fixed expected metric ranges.
- Verify sensitivity changes the mask predictably without altering pixels outside the cup.
- Verify unsupported formats, oversized files, low-resolution images, failed decoding, extreme masks, and low-confidence segmentation produce actionable errors or warnings.
- Component-test the complete state flow and ensure scores are suppressed when confidence is insufficient.
- Run browser tests for file selection, alignment controls, mask preview, result annotations, reset behavior, and refresh-based image disposal.
- Acceptance criteria: no network request during analysis; deterministic output; analysis under one second on a typical desktop at 512×512; exact weighted score; no persistence; no more than two coaching tips; production build and TypeScript checks pass.

## Assumptions and Deferred Work

- V1 supports hearts only and requires the system file picker.
- There is no backend, account, analytics, database, image persistence, history, drag-and-drop, clipboard paste, camera integration, or LLM/API call.
- Cup detection is manually confirmed; automatic circle detection is deferred.
- Mask editing is limited to cup position, cup size, and sensitivity; brush/eraser tools are deferred.
- Tulips, rosettas, personal-progress tracking, native pixel decoders, on-device ML, and mobile releases follow only after heart segmentation is validated.
- Thresholds live in one versioned configuration object so they can be calibrated without rewriting the algorithms.
