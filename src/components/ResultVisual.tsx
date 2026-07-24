import { Image, StyleSheet, View } from "react-native";

export function ResultVisual({ previewUri, overlayUri }: { previewUri: string; overlayUri: string }) {
  return (
    <View style={styles.stage}>
      <Image source={{ uri: previewUri }} style={styles.layer} resizeMode="cover" />
      <Image source={{ uri: overlayUri }} style={styles.layer} resizeMode="cover" />
    </View>
  );
}

const styles = StyleSheet.create({
  stage: { width: "100%", aspectRatio: 1, borderRadius: 24, overflow: "hidden", backgroundColor: "#2a211c", position: "relative" },
  layer: { position: "absolute", width: "100%", height: "100%" },
});
