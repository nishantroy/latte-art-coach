import { useMemo, useRef, useState } from "react";
import { PanResponder, Pressable, StyleSheet, Text, View } from "react-native";

type Props = { value: number; onChange: (value: number) => void };

export function SensitivitySlider({ value, onChange }: Props) {
  const [width, setWidth] = useState(1);
  const widthRef = useRef(width);
  widthRef.current = width;
  const setFromX = (x: number) => onChange(Math.round(Math.max(-20, Math.min(20, (x / widthRef.current) * 40 - 20))));
  const responder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponder: () => true,
        onPanResponderGrant: (event) => setFromX(event.nativeEvent.locationX),
        onPanResponderMove: (event) => setFromX(event.nativeEvent.locationX),
      }),
    [],
  );
  const position = ((value + 20) / 40) * 100;
  return (
    <View>
      <View style={styles.labels}>
        <Text style={styles.label}>Less foam</Text>
        <Text style={styles.value}>{value > 0 ? `+${value}` : value}</Text>
        <Text style={styles.label}>More foam</Text>
      </View>
      <Pressable
        accessibilityRole="adjustable"
        accessibilityLabel="Foam sensitivity"
        accessibilityValue={{ min: -20, max: 20, now: value }}
        onLayout={(event) => setWidth(event.nativeEvent.layout.width)}
        style={styles.trackHitbox}
        {...responder.panHandlers}
      >
        <View style={styles.track} />
        <View style={[styles.fill, { width: `${position}%` }]} />
        <View style={[styles.thumb, { left: `${position}%` }]} />
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  labels: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: 6 },
  label: { color: "#76685d", fontSize: 12 },
  value: { color: "#2b2019", fontSize: 13, fontWeight: "700", fontVariant: ["tabular-nums"] },
  trackHitbox: { height: 34, justifyContent: "center", position: "relative" },
  track: { height: 6, borderRadius: 6, backgroundColor: "#ded7cf" },
  fill: { position: "absolute", left: 0, height: 6, borderRadius: 6, backgroundColor: "#2e7566" },
  thumb: { position: "absolute", width: 22, height: 22, marginLeft: -11, borderRadius: 11, backgroundColor: "#fff", borderWidth: 3, borderColor: "#2e7566" },
});
