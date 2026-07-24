import { useMemo, useState } from "react";
import * as ImagePicker from "expo-image-picker";
import {
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";
import {
  ANALYSIS_CONFIG,
  analyzeLatteArt,
  segmentFoam,
  type AnalysisResult,
  type ComponentScores,
  type CupCircle,
} from "../src/analysis-core";
import { CupEditor } from "../src/components/CupEditor";
import { ResultVisual } from "../src/components/ResultVisual";
import { SensitivitySlider } from "../src/components/SensitivitySlider";
import {
  decodePickerAsset,
  maskOverlayDataUri,
  resultOverlayDataUri,
  type DecodedPhoto,
} from "../src/platform/image";

type Step = "upload" | "align" | "results";

const INITIAL_CUP: CupCircle = { centerX: 256, centerY: 256, radius: 215.04 };
const MAX_FILE_BYTES = 20 * 1024 * 1024;
const SUPPORTED_MIME = new Set(["image/jpeg", "image/png", "image/webp"]);
const SCORE_LABELS: Array<[keyof ComponentScores, string]> = [
  ["symmetry", "Symmetry"],
  ["centering", "Centering"],
  ["coverage", "Coverage"],
  ["contrast", "Contrast"],
  ["heartShape", "Heart shape"],
];

function PrimaryButton({ label, onPress, disabled = false }: { label: string; onPress: () => void; disabled?: boolean }) {
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={({ hovered, pressed }) => [styles.primaryButton, hovered && styles.primaryButtonHover, pressed && styles.buttonPressed, disabled && styles.buttonDisabled]}
    >
      <Text style={styles.primaryButtonText}>{label}</Text>
    </Pressable>
  );
}

function SecondaryButton({ label, onPress }: { label: string; onPress: () => void }) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ hovered, pressed }) => [styles.secondaryButton, hovered && styles.secondaryButtonHover, pressed && styles.buttonPressed]}
    >
      <Text style={styles.secondaryButtonText}>{label}</Text>
    </Pressable>
  );
}

function Steps({ step }: { step: Step }) {
  const current = step === "upload" ? 0 : step === "align" ? 1 : 2;
  return (
    <View style={styles.steps} accessibilityLabel={`Step ${current + 1} of 3`}>
      {["Choose photo", "Frame & tune", "Your review"].map((label, index) => (
        <View key={label} style={styles.stepItem}>
          <View style={[styles.stepDot, index <= current && styles.stepDotActive]}>
            <Text style={[styles.stepNumber, index <= current && styles.stepNumberActive]}>{index + 1}</Text>
          </View>
          <Text style={[styles.stepText, index === current && styles.stepTextActive]}>{label}</Text>
        </View>
      ))}
    </View>
  );
}

function ScoreRow({ label, value }: { label: string; value: number }) {
  return (
    <View style={styles.scoreRow}>
      <View style={styles.scoreMeta}>
        <Text style={styles.scoreLabel}>{label}</Text>
        <Text style={styles.scoreValue}>{value}</Text>
      </View>
      <View style={styles.scoreTrack}>
        <View style={[styles.scoreFill, { width: `${value}%` }]} />
      </View>
    </View>
  );
}

function UploadPanel({ onChoose, busy, error }: { onChoose: () => void; busy: boolean; error: string | null }) {
  return (
    <View style={styles.uploadShell}>
      <View style={styles.uploadIcon}>
        <Text style={styles.uploadIconCup}>♥</Text>
      </View>
      <Text style={styles.uploadTitle}>Choose your latest pour</Text>
      <Text style={styles.uploadCopy}>Pick a clear, overhead photo of a heart. The image stays in this browser tab and is never uploaded.</Text>
      <View style={styles.formatPills}>
        {["JPEG", "PNG", "WebP", "≤ 20 MB"].map((item) => <Text key={item} style={styles.pill}>{item}</Text>)}
      </View>
      {error ? <Text accessibilityRole="alert" style={styles.errorText}>{error}</Text> : null}
      {busy ? <ActivityIndicator color="#2e7566" size="large" /> : <PrimaryButton label="Choose a photo" onPress={onChoose} />}
      <Text style={styles.privacyLine}>Local analysis · no account · no AI service</Text>
    </View>
  );
}

export default function HomeScreen() {
  const [step, setStep] = useState<Step>("upload");
  const [photo, setPhoto] = useState<DecodedPhoto | null>(null);
  const [cup, setCup] = useState<CupCircle>(INITIAL_CUP);
  const [sensitivity, setSensitivity] = useState(0);
  const [result, setResult] = useState<AnalysisResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const previewSegmentation = useMemo(() => {
    if (!photo || step !== "align") return null;
    const segmentation = segmentFoam({ image: photo.pixels, cup, pattern: "heart", foamSensitivity: sensitivity });
    return {
      ...segmentation,
      uri: maskOverlayDataUri(segmentation.mask, photo.pixels.width, photo.pixels.height),
    };
  }, [photo, cup, sensitivity, step]);

  const resultOverlay = useMemo(() => {
    if (!photo || !result) return "";
    return resultOverlayDataUri(result, cup, photo.pixels.width, photo.pixels.height);
  }, [photo, result, cup]);

  const choosePhoto = async () => {
    setError(null);
    setBusy(true);
    try {
      const selection = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ["images"], quality: 1 });
      if (selection.canceled) return;
      const asset = selection.assets[0];
      const file = (asset as ImagePicker.ImagePickerAsset & { file?: File }).file;
      const bytes = asset.fileSize ?? file?.size ?? 0;
      const extension = asset.fileName?.split(".").pop()?.toLowerCase();
      const mime = asset.mimeType?.toLowerCase();
      const supportedExtension = ["jpg", "jpeg", "png", "webp"].includes(extension ?? "");
      if ((mime && !SUPPORTED_MIME.has(mime)) || (!mime && !supportedExtension)) {
        throw new Error("Use a JPEG, PNG, or WebP photo. HEIC is not supported in this first version.");
      }
      if (bytes > MAX_FILE_BYTES) throw new Error("That photo is larger than 20 MB. Choose a smaller export.");
      const decoded = await decodePickerAsset(asset);
      if (Math.min(decoded.sourceWidth, decoded.sourceHeight) < 640) {
        throw new Error("Choose a photo at least 640 pixels on its shortest side.");
      }
      setPhoto(decoded);
      setCup(INITIAL_CUP);
      setSensitivity(0);
      setResult(null);
      setStep("align");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "The photo could not be opened.");
    } finally {
      setBusy(false);
    }
  };

  const runAnalysis = () => {
    if (!photo) return;
    const started = performance.now();
    const analysis = analyzeLatteArt({ image: photo.pixels, cup, pattern: "heart", foamSensitivity: sensitivity });
    if (performance.now() - started > 1000) analysis.warnings.push("Analysis took longer than expected on this device.");
    setResult(analysis);
    setStep("results");
  };

  const reset = () => {
    setStep("upload");
    setPhoto(null);
    setResult(null);
    setCup(INITIAL_CUP);
    setSensitivity(0);
    setError(null);
  };

  return (
    <SafeAreaView style={styles.safeArea}>
      <ScrollView contentContainerStyle={styles.page}>
        <View style={styles.header}>
          <View style={styles.brandRow}>
            <View style={styles.brandMark}><Text style={styles.brandMarkText}>L</Text></View>
            <Text style={styles.brand}>Latte Art Coach</Text>
          </View>
          <View style={styles.localBadge}><View style={styles.localDot} /><Text style={styles.localText}>Runs locally</Text></View>
        </View>

        <View style={styles.hero}>
          <Text style={styles.eyebrow}>HEART PRACTICE · WEB MVP</Text>
          <Text style={styles.headline}>See your pour more clearly.</Text>
          <Text style={styles.subhead}>A private, visual review of symmetry, centering, coverage, contrast, and heart shape—without uploading your photo.</Text>
        </View>

        <Steps step={step} />

        {step === "upload" ? <UploadPanel onChoose={choosePhoto} busy={busy} error={error} /> : null}

        {step === "align" && photo && previewSegmentation ? (
          <View style={styles.workspace}>
            <View style={styles.visualColumn}>
              <CupEditor previewUri={photo.previewUri} maskUri={previewSegmentation.uri} cup={cup} onCupChange={setCup} />
            </View>
            <View style={styles.controlCard}>
              <Text style={styles.cardKicker}>PREPARE THE REVIEW</Text>
              <Text style={styles.cardTitle}>Frame the inside of your cup</Text>
              <Text style={styles.cardCopy}>Drag the circle to move it. Drag the white handle to resize it just inside the rim.</Text>
              <View style={styles.divider} />
              <View style={styles.controlHeading}>
                <Text style={styles.controlLabel}>Foam sensitivity</Text>
                <Text style={styles.coverageText}>{Math.round(previewSegmentation.coverage * 100)}% detected</Text>
              </View>
              <Text style={styles.controlHelp}>Tune until the mint overlay follows the white heart—not glare or the ceramic rim.</Text>
              <SensitivitySlider value={sensitivity} onChange={setSensitivity} />
              <View style={styles.confidenceBox}>
                <Text style={styles.confidenceLabel}>Live segmentation confidence</Text>
                <Text style={styles.confidenceValue}>{Math.round(previewSegmentation.confidence * 100)}%</Text>
              </View>
              <View style={styles.buttonStack}>
                <PrimaryButton label="Analyze this heart" onPress={runAnalysis} />
                <SecondaryButton label="Choose a different photo" onPress={reset} />
              </View>
            </View>
          </View>
        ) : null}

        {step === "results" && photo && result ? (
          <View style={styles.resultsWrap}>
            <View style={styles.workspace}>
              <View style={styles.visualColumn}>
                <ResultVisual previewUri={photo.previewUri} overlayUri={resultOverlay} />
                <View style={styles.annotationLegend}>
                  <Text style={styles.legendMint}>● Foam outline</Text>
                  <Text style={styles.legendGold}>— Symmetry axis</Text>
                  <Text style={styles.legendWhite}>+ Cup center</Text>
                </View>
              </View>
              <View style={styles.resultCard}>
                <Text style={styles.cardKicker}>YOUR REVIEW</Text>
                <View style={styles.totalScoreRow}>
                  <View>
                    <Text style={styles.totalLabel}>Visual analysis score</Text>
                    <Text style={styles.totalCaption}>Transparent weighted result</Text>
                  </View>
                  <View style={[styles.scoreDisc, result.overallScore === null && styles.scoreDiscMuted]}>
                    <Text style={styles.scoreDiscValue}>{result.overallScore ?? "—"}</Text>
                    <Text style={styles.scoreDiscUnit}>/ 100</Text>
                  </View>
                </View>
                {result.overallScore === null ? <Text style={styles.noScore}>Adjust the photo or foam sensitivity for a reliable score.</Text> : null}
                <View style={styles.scoreList}>
                  {SCORE_LABELS.map(([key, label]) => <ScoreRow key={key} label={label} value={result.componentScores[key]} />)}
                </View>
                <Text style={styles.confidenceResult}>Segmentation confidence · {Math.round(result.metrics.segmentationConfidence * 100)}%</Text>
              </View>
            </View>

            {result.warnings.length ? (
              <View style={styles.warningCard}>
                <Text style={styles.warningTitle}>Photo notes</Text>
                {result.warnings.map((warning) => <Text key={warning} style={styles.warningText}>• {warning}</Text>)}
              </View>
            ) : null}

            <View style={styles.tipsSection}>
              <Text style={styles.sectionEyebrow}>NEXT POUR</Text>
              <Text style={styles.sectionTitle}>{result.tips.length ? "Two things to practice" : "Try another framing"}</Text>
              <View style={styles.tipGrid}>
                {result.tips.map((tip, index) => (
                  <View key={tip.metric} style={styles.tipCard}>
                    <Text style={styles.tipNumber}>0{index + 1}</Text>
                    <Text style={styles.tipTitle}>{tip.title}</Text>
                    <Text style={styles.tipObservation}>{tip.observation}</Text>
                    <View style={styles.tipRule} />
                    <Text style={styles.tipSuggestion}>{tip.suggestion}</Text>
                  </View>
                ))}
              </View>
            </View>
            <View style={styles.resultsActions}>
              <PrimaryButton label="Analyze another photo" onPress={reset} />
              <SecondaryButton label="Adjust this photo" onPress={() => setStep("align")} />
            </View>
          </View>
        ) : null}

        <View style={styles.footer}>
          <Text style={styles.footerText}>Observations come from visible geometry only. Coaching suggestions are possibilities, not diagnoses.</Text>
          <Text style={styles.footerVersion}>Analysis rules v{ANALYSIS_CONFIG.version}</Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: "#f7f3ed" },
  page: { minHeight: "100%", paddingHorizontal: 24, paddingBottom: 34 },
  header: { width: "100%", maxWidth: 1120, alignSelf: "center", paddingVertical: 24, flexDirection: "row", alignItems: "center", justifyContent: "space-between" },
  brandRow: { flexDirection: "row", alignItems: "center", gap: 10 },
  brandMark: { width: 30, height: 30, borderRadius: 9, backgroundColor: "#2e7566", alignItems: "center", justifyContent: "center" },
  brandMarkText: { color: "#fff", fontSize: 17, fontWeight: "800" },
  brand: { color: "#2b2019", fontSize: 16, fontWeight: "800", letterSpacing: -0.3 },
  localBadge: { flexDirection: "row", alignItems: "center", gap: 7, paddingHorizontal: 11, paddingVertical: 7, borderRadius: 20, backgroundColor: "#e4eee8" },
  localDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: "#2e7566" },
  localText: { color: "#2e7566", fontSize: 12, fontWeight: "700" },
  hero: { width: "100%", maxWidth: 760, alignSelf: "center", alignItems: "center", paddingTop: 42, paddingBottom: 34 },
  eyebrow: { color: "#a55d3a", fontSize: 11, fontWeight: "800", letterSpacing: 1.8, marginBottom: 16 },
  headline: { color: "#291e18", textAlign: "center", fontSize: 54, lineHeight: 58, fontWeight: "800", letterSpacing: -2.3 },
  subhead: { color: "#76685d", textAlign: "center", fontSize: 17, lineHeight: 27, maxWidth: 650, marginTop: 17 },
  steps: { width: "100%", maxWidth: 620, alignSelf: "center", flexDirection: "row", justifyContent: "space-between", marginBottom: 34 },
  stepItem: { alignItems: "center", flex: 1, gap: 8 },
  stepDot: { width: 30, height: 30, borderRadius: 15, backgroundColor: "#e4ddd4", alignItems: "center", justifyContent: "center" },
  stepDotActive: { backgroundColor: "#2e7566" },
  stepNumber: { color: "#8d8075", fontSize: 12, fontWeight: "800" },
  stepNumberActive: { color: "#fff" },
  stepText: { color: "#9a8d82", fontSize: 11, fontWeight: "600", textAlign: "center" },
  stepTextActive: { color: "#2b2019" },
  uploadShell: { width: "100%", maxWidth: 730, minHeight: 410, alignSelf: "center", alignItems: "center", justifyContent: "center", backgroundColor: "#fffdf9", borderWidth: 1, borderColor: "#dfd6cc", borderRadius: 30, padding: 38 },
  uploadIcon: { width: 72, height: 72, borderRadius: 24, alignItems: "center", justifyContent: "center", backgroundColor: "#e4eee8", marginBottom: 22 },
  uploadIconCup: { color: "#2e7566", fontSize: 30, fontWeight: "800" },
  uploadTitle: { color: "#2b2019", fontSize: 25, fontWeight: "800", letterSpacing: -0.6 },
  uploadCopy: { color: "#76685d", fontSize: 15, lineHeight: 23, textAlign: "center", maxWidth: 470, marginTop: 10 },
  formatPills: { flexDirection: "row", flexWrap: "wrap", justifyContent: "center", gap: 7, marginVertical: 22 },
  pill: { color: "#76685d", fontSize: 11, fontWeight: "700", backgroundColor: "#f0ebe5", paddingHorizontal: 10, paddingVertical: 6, borderRadius: 12 },
  errorText: { color: "#a13f31", backgroundColor: "#fae9e3", borderRadius: 10, paddingHorizontal: 12, paddingVertical: 9, marginBottom: 15, textAlign: "center", maxWidth: 500 },
  privacyLine: { color: "#9a8d82", fontSize: 11, marginTop: 14 },
  primaryButton: { backgroundColor: "#2e7566", borderRadius: 14, paddingHorizontal: 24, paddingVertical: 15, minWidth: 190, alignItems: "center" },
  primaryButtonHover: { backgroundColor: "#24685a" },
  secondaryButton: { borderWidth: 1, borderColor: "#d8cfc5", borderRadius: 14, paddingHorizontal: 22, paddingVertical: 14, minWidth: 190, alignItems: "center", backgroundColor: "#fffdf9" },
  secondaryButtonHover: { backgroundColor: "#f4efe9" },
  buttonPressed: { transform: [{ scale: 0.98 }], opacity: 0.92 },
  buttonDisabled: { opacity: 0.45 },
  primaryButtonText: { color: "#fff", fontSize: 14, fontWeight: "800" },
  secondaryButtonText: { color: "#49382d", fontSize: 14, fontWeight: "700" },
  workspace: { width: "100%", maxWidth: 1050, alignSelf: "center", flexDirection: "row", flexWrap: "wrap", gap: 28, alignItems: "flex-start" },
  visualColumn: { flexGrow: 1, flexBasis: 440, minWidth: 280, maxWidth: 550 },
  controlCard: { flexGrow: 1, flexBasis: 350, minWidth: 280, maxWidth: 470, backgroundColor: "#fffdf9", borderWidth: 1, borderColor: "#dfd6cc", borderRadius: 26, padding: 28 },
  resultCard: { flexGrow: 1, flexBasis: 350, minWidth: 280, maxWidth: 470, backgroundColor: "#fffdf9", borderWidth: 1, borderColor: "#dfd6cc", borderRadius: 26, padding: 28 },
  cardKicker: { color: "#a55d3a", fontSize: 10, fontWeight: "800", letterSpacing: 1.6, marginBottom: 11 },
  cardTitle: { color: "#2b2019", fontSize: 27, lineHeight: 32, fontWeight: "800", letterSpacing: -0.6 },
  cardCopy: { color: "#76685d", fontSize: 14, lineHeight: 22, marginTop: 10 },
  divider: { height: 1, backgroundColor: "#ebe4dc", marginVertical: 24 },
  controlHeading: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", gap: 12 },
  controlLabel: { color: "#2b2019", fontSize: 15, fontWeight: "800" },
  coverageText: { color: "#2e7566", fontSize: 12, fontWeight: "800" },
  controlHelp: { color: "#76685d", fontSize: 12, lineHeight: 18, marginTop: 7, marginBottom: 15 },
  confidenceBox: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginTop: 20, padding: 13, borderRadius: 12, backgroundColor: "#f0ebe5" },
  confidenceLabel: { color: "#76685d", fontSize: 12 },
  confidenceValue: { color: "#2b2019", fontSize: 13, fontWeight: "800" },
  buttonStack: { gap: 10, marginTop: 24 },
  resultsWrap: { width: "100%" },
  annotationLegend: { flexDirection: "row", flexWrap: "wrap", gap: 15, paddingTop: 12 },
  legendMint: { color: "#2e7566", fontSize: 11, fontWeight: "700" },
  legendGold: { color: "#a76e1e", fontSize: 11, fontWeight: "700" },
  legendWhite: { color: "#76685d", fontSize: 11, fontWeight: "700" },
  totalScoreRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 15 },
  totalLabel: { color: "#2b2019", fontSize: 17, fontWeight: "800" },
  totalCaption: { color: "#9a8d82", fontSize: 11, marginTop: 3 },
  scoreDisc: { width: 88, height: 88, borderRadius: 44, borderWidth: 7, borderColor: "#2e7566", backgroundColor: "#eaf2ee", alignItems: "center", justifyContent: "center" },
  scoreDiscMuted: { borderColor: "#b9afa5", backgroundColor: "#f0ebe5" },
  scoreDiscValue: { color: "#2b2019", fontSize: 28, lineHeight: 30, fontWeight: "900", fontVariant: ["tabular-nums"] },
  scoreDiscUnit: { color: "#76685d", fontSize: 9, fontWeight: "700" },
  noScore: { color: "#a13f31", fontSize: 12, lineHeight: 18, marginTop: 12 },
  scoreList: { marginTop: 24, gap: 14 },
  scoreRow: { gap: 6 },
  scoreMeta: { flexDirection: "row", justifyContent: "space-between" },
  scoreLabel: { color: "#49382d", fontSize: 12, fontWeight: "700" },
  scoreValue: { color: "#2b2019", fontSize: 12, fontWeight: "900", fontVariant: ["tabular-nums"] },
  scoreTrack: { height: 6, borderRadius: 5, backgroundColor: "#e8e0d7", overflow: "hidden" },
  scoreFill: { height: "100%", borderRadius: 5, backgroundColor: "#2e7566" },
  confidenceResult: { color: "#76685d", fontSize: 11, marginTop: 21, borderTopWidth: 1, borderTopColor: "#ebe4dc", paddingTop: 15 },
  warningCard: { width: "100%", maxWidth: 1050, alignSelf: "center", marginTop: 24, padding: 18, borderRadius: 16, backgroundColor: "#fff4df", borderWidth: 1, borderColor: "#edd8ad" },
  warningTitle: { color: "#6b4a1d", fontSize: 13, fontWeight: "800", marginBottom: 5 },
  warningText: { color: "#7e6138", fontSize: 12, lineHeight: 19 },
  tipsSection: { width: "100%", maxWidth: 1050, alignSelf: "center", marginTop: 45 },
  sectionEyebrow: { color: "#a55d3a", fontSize: 10, fontWeight: "800", letterSpacing: 1.6 },
  sectionTitle: { color: "#2b2019", fontSize: 28, fontWeight: "800", letterSpacing: -0.7, marginTop: 7, marginBottom: 18 },
  tipGrid: { flexDirection: "row", flexWrap: "wrap", gap: 16 },
  tipCard: { flexGrow: 1, flexBasis: 360, backgroundColor: "#fffdf9", borderRadius: 20, borderWidth: 1, borderColor: "#dfd6cc", padding: 23 },
  tipNumber: { color: "#a55d3a", fontSize: 11, fontWeight: "900", letterSpacing: 1.4 },
  tipTitle: { color: "#2b2019", fontSize: 19, fontWeight: "800", marginTop: 8 },
  tipObservation: { color: "#76685d", fontSize: 13, lineHeight: 20, marginTop: 7 },
  tipRule: { width: 34, height: 3, backgroundColor: "#2e7566", borderRadius: 2, marginVertical: 15 },
  tipSuggestion: { color: "#49382d", fontSize: 13, lineHeight: 21, fontWeight: "600" },
  resultsActions: { width: "100%", maxWidth: 1050, alignSelf: "center", flexDirection: "row", flexWrap: "wrap", gap: 10, marginTop: 25 },
  footer: { width: "100%", maxWidth: 1050, alignSelf: "center", marginTop: 55, paddingTop: 20, borderTopWidth: 1, borderTopColor: "#dfd6cc", flexDirection: "row", flexWrap: "wrap", gap: 12, justifyContent: "space-between" },
  footerText: { color: "#93877c", fontSize: 11, lineHeight: 17, maxWidth: 650 },
  footerVersion: { color: "#93877c", fontSize: 11, fontWeight: "700" },
});
