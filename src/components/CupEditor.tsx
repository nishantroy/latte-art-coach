import { useEffect, useMemo, useRef, useState } from "react";
import { Image, PanResponder, StyleSheet, Text, View } from "react-native";
import type { CupCircle } from "../analysis-core";

type Props = {
  previewUri: string;
  maskUri?: string;
  cup: CupCircle;
  onCupChange: (cup: CupCircle) => void;
};

type DragMode = "move" | "resize" | null;

export function CupEditor({ previewUri, maskUri, cup, onCupChange }: Props) {
  const [size, setSize] = useState(1);
  const cupRef = useRef(cup);
  const startCup = useRef(cup);
  const mode = useRef<DragMode>(null);
  const sizeRef = useRef(size);
  useEffect(() => { cupRef.current = cup; }, [cup]);
  useEffect(() => { sizeRef.current = size; }, [size]);

  const responder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponder: () => true,
        onPanResponderGrant: (event) => {
          startCup.current = cupRef.current;
          const scale = 512 / sizeRef.current;
          const x = event.nativeEvent.locationX * scale;
          const y = event.nativeEvent.locationY * scale;
          const handleX = cupRef.current.centerX + cupRef.current.radius * 0.707;
          const handleY = cupRef.current.centerY + cupRef.current.radius * 0.707;
          mode.current = Math.hypot(x - handleX, y - handleY) < 38 ? "resize" : "move";
        },
        onPanResponderMove: (_event, gesture) => {
          const scale = 512 / sizeRef.current;
          const base = startCup.current;
          if (mode.current === "resize") {
            const radius = Math.max(70, Math.min(255, base.radius + (gesture.dx + gesture.dy) * scale * 0.5));
            onCupChange({ ...base, radius });
          } else {
            const centerX = Math.max(0, Math.min(512, base.centerX + gesture.dx * scale));
            const centerY = Math.max(0, Math.min(512, base.centerY + gesture.dy * scale));
            onCupChange({ ...base, centerX, centerY });
          }
        },
        onPanResponderRelease: () => { mode.current = null; },
      }),
    [onCupChange],
  );

  const scale = size / 512;
  const diameter = cup.radius * 2 * scale;
  return (
    <View>
      <View
        accessibilityLabel="Adjustable cup boundary"
        onLayout={(event) => setSize(event.nativeEvent.layout.width)}
        style={styles.stage}
        {...responder.panHandlers}
      >
        <Image source={{ uri: previewUri }} style={styles.image} resizeMode="cover" />
        {maskUri ? <Image source={{ uri: maskUri }} style={styles.mask} resizeMode="cover" /> : null}
        <View
          pointerEvents="none"
          style={[
            styles.circle,
            {
              width: diameter,
              height: diameter,
              borderRadius: diameter / 2,
              left: cup.centerX * scale - diameter / 2,
              top: cup.centerY * scale - diameter / 2,
            },
          ]}
        />
        <View
          pointerEvents="none"
          style={[
            styles.center,
            { left: cup.centerX * scale - 8, top: cup.centerY * scale - 8 },
          ]}
        />
        <View
          pointerEvents="none"
          style={[
            styles.handle,
            {
              left: (cup.centerX + cup.radius * 0.707) * scale - 11,
              top: (cup.centerY + cup.radius * 0.707) * scale - 11,
            },
          ]}
        />
      </View>
      <View style={styles.legend}>
        <View style={styles.swatch} />
        <Text style={styles.legendText}>Mint overlay shows what the app sees as white foam.</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  stage: { width: "100%", aspectRatio: 1, overflow: "hidden", borderRadius: 24, backgroundColor: "#2a211c", position: "relative" },
  image: { width: "100%", height: "100%", position: "absolute" },
  mask: { width: "100%", height: "100%", position: "absolute" },
  circle: { position: "absolute", borderWidth: 2, borderColor: "rgba(255,255,255,.95)", borderStyle: "dashed", backgroundColor: "rgba(255,255,255,.025)" },
  center: { position: "absolute", width: 16, height: 16, borderWidth: 2, borderColor: "#fff", borderRadius: 8, backgroundColor: "rgba(46,117,102,.8)" },
  handle: { position: "absolute", width: 22, height: 22, borderRadius: 11, backgroundColor: "#fff", borderWidth: 4, borderColor: "#2e7566" },
  legend: { marginTop: 11, flexDirection: "row", alignItems: "center", gap: 8 },
  swatch: { width: 12, height: 12, borderRadius: 3, backgroundColor: "#57dcb9" },
  legendText: { color: "#76685d", fontSize: 12, flex: 1 },
});
