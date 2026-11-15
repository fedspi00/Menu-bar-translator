#!/bin/bash
# Draws the app icon and writes it as .icns to $1.
set -euo pipefail

OUT="${1:?usage: make-icon.sh <output.icns>}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/icon.swift" <<'SWIFT'
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = size * 0.06
    let body = rect.insetBy(dx: inset, dy: inset)
    let path = NSBezierPath(roundedRect: body, xRadius: size * 0.22, yRadius: size * 0.22)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.20, green: 0.32, blue: 0.85, alpha: 1),
    ])
    gradient?.draw(in: path, angle: -90)

    let text = "A文" as NSString
    let font = NSFont.systemFont(ofSize: size * 0.40, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2),
        withAttributes: attributes
    )
    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

xcrun --sdk macosx swiftc -O "$TMP/icon.swift" -o "$TMP/icon"
"$TMP/icon" "$TMP/base.png"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
    px="${spec%%:*}"
    name="${spec##*:}"
    sips -z "$px" "$px" "$TMP/base.png" --out "$ICONSET/icon_${name}.png" >/dev/null
done

iconutil --convert icns "$ICONSET" --output "$OUT"
