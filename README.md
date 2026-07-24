# Latte Art Coach

A local-only Expo Router web app that reviews heart-shaped latte art from an uploaded photo. Images are analyzed in browser memory and are discarded on refresh.

## Run locally

```bash
pnpm install
pnpm web
```

Then open the local URL printed by Expo. Use the system picker to choose a JPEG, PNG, or WebP photo.

## Verify

```bash
pnpm test
pnpm typecheck
pnpm build:web
```

The pure TypeScript analysis engine lives in `src/analysis-core`. It performs Lab color conversion, deterministic two-cluster foam segmentation, mask cleanup, geometric measurement, scoring, and rules-based coaching without a backend or model call.

See [PLAN.md](./PLAN.md) for the canonical product and implementation plan.
