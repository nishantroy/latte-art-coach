import type { ImagePickerAsset } from "expo-image-picker";
import type { AnalysisResult, CupCircle, PixelBuffer } from "../analysis-core";

export type DecodedPhoto = {
  pixels: PixelBuffer;
  previewUri: string;
  sourceWidth: number;
  sourceHeight: number;
};

const OUTPUT_SIZE = 512;

function requireWebCanvas() {
  if (typeof document === "undefined") {
    throw new Error("Photo decoding is available in the web MVP only.");
  }
}

function loadImage(uri: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const image = new window.Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error("This photo could not be decoded. Try exporting it as JPEG, PNG, or WebP."));
    image.src = uri;
  });
}

function drawCover(context: CanvasRenderingContext2D, image: HTMLImageElement, size: number) {
  const scale = Math.max(size / image.naturalWidth, size / image.naturalHeight);
  const width = image.naturalWidth * scale;
  const height = image.naturalHeight * scale;
  context.drawImage(image, (size - width) / 2, (size - height) / 2, width, height);
}

export async function decodePickerAsset(asset: ImagePickerAsset): Promise<DecodedPhoto> {
  requireWebCanvas();
  const image = await loadImage(asset.uri);
  const canvas = document.createElement("canvas");
  canvas.width = OUTPUT_SIZE;
  canvas.height = OUTPUT_SIZE;
  const context = canvas.getContext("2d", { willReadFrequently: true });
  if (!context) throw new Error("Your browser does not support local image analysis.");
  drawCover(context, image, OUTPUT_SIZE);
  const data = context.getImageData(0, 0, OUTPUT_SIZE, OUTPUT_SIZE);
  return {
    pixels: { width: OUTPUT_SIZE, height: OUTPUT_SIZE, rgba: data.data },
    previewUri: canvas.toDataURL("image/jpeg", 0.92),
    sourceWidth: image.naturalWidth,
    sourceHeight: image.naturalHeight,
  };
}

export function maskOverlayDataUri(mask: Uint8Array, width: number, height: number) {
  requireWebCanvas();
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) return "";
  const overlay = context.createImageData(width, height);
  for (let i = 0; i < mask.length; i += 1) {
    if (!mask[i]) continue;
    overlay.data[i * 4] = 87;
    overlay.data[i * 4 + 1] = 220;
    overlay.data[i * 4 + 2] = 185;
    overlay.data[i * 4 + 3] = 150;
  }
  context.putImageData(overlay, 0, 0);
  return canvas.toDataURL("image/png");
}

export function resultOverlayDataUri(result: AnalysisResult, cup: CupCircle, width: number, height: number) {
  requireWebCanvas();
  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) return "";
  context.lineCap = "round";
  context.lineJoin = "round";

  context.strokeStyle = "rgba(255,255,255,.86)";
  context.lineWidth = 2;
  context.setLineDash([8, 7]);
  context.beginPath();
  context.arc(cup.centerX, cup.centerY, cup.radius, 0, Math.PI * 2);
  context.stroke();
  context.setLineDash([]);

  const outline = result.annotations.find((annotation) => annotation.type === "outline");
  if (outline?.type === "outline") {
    context.fillStyle = "rgba(87,220,185,.8)";
    for (const point of outline.points) context.fillRect(point.x - 1, point.y - 1, 3, 3);
  }

  const centroid = result.annotations.find((annotation) => annotation.type === "centroid");
  if (centroid?.type === "centroid") {
    const radians = (result.axisAngleDegrees * Math.PI) / 180;
    const axisX = Math.sin(radians);
    const axisY = -Math.cos(radians);
    context.strokeStyle = "rgba(255,205,112,.95)";
    context.lineWidth = 2;
    context.beginPath();
    context.moveTo(centroid.x - axisX * cup.radius, centroid.y - axisY * cup.radius);
    context.lineTo(centroid.x + axisX * cup.radius, centroid.y + axisY * cup.radius);
    context.stroke();
    context.fillStyle = "#ffcd70";
    context.beginPath();
    context.arc(centroid.x, centroid.y, 6, 0, Math.PI * 2);
    context.fill();
  }

  context.strokeStyle = "rgba(255,255,255,.92)";
  context.lineWidth = 2;
  context.beginPath();
  context.moveTo(cup.centerX - 8, cup.centerY);
  context.lineTo(cup.centerX + 8, cup.centerY);
  context.moveTo(cup.centerX, cup.centerY - 8);
  context.lineTo(cup.centerX, cup.centerY + 8);
  context.stroke();
  return canvas.toDataURL("image/png");
}
