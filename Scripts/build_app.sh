#!/bin/bash
# MacGuard.app paketini sıfırdan üretir.
#   ./Scripts/build_app.sh            -> build.noindex/MacGuard.app
#   ./Scripts/build_app.sh --install  -> /Applications altına da kopyalar
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="MacGuard"
BUNDLE_ID="com.furkanberkay.macguard"
OUT="build.noindex/${APP_NAME}.app"

echo "▸ Swift derleniyor (release)…"
swift build -c release

echo "▸ Paket hazırlanıyor…"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

cp ".build/release/${APP_NAME}" "$OUT/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist"       "$OUT/Contents/Info.plist"
printf 'APPL????' > "$OUT/Contents/PkgInfo"

echo "▸ İkon üretiliyor…"
ICONSET="build.noindex/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
if swift Scripts/make_icon.swift "build.noindex/icon-1024.png" >/dev/null 2>&1; then
  for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
              "128 128x128" "256 128x128@2x" "256 256x256" \
              "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" "build.noindex/icon-1024.png" --out "$ICONSET/icon_$2.png" >/dev/null 2>&1
  done
  iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns" 2>/dev/null \
    && echo "  ikon eklendi" || echo "  ikon atlandı (zararsız)"
else
  echo "  ikon üretilemedi, varsayılanla devam ediliyor (zararsız)"
fi
rm -rf "$ICONSET" build.noindex/icon-1024.png

SIGN_DIR="$HOME/Library/Application Support/MacGuard/signing"
SIGN_KEYCHAIN="$SIGN_DIR/macguard-signing.keychain-db"
if [ -f "$SIGN_DIR/identity.sha1" ] && [ -f "$SIGN_KEYCHAIN" ]; then
  echo "▸ İmzalanıyor (yerel kimlik)…"
  # codesign kimliği yalnız arama listesindeki anahtar zincirlerinde arıyor;
  # listeye imza süresince eklenip hemen eski hâline döndürülüyor.
  ORIGINAL_KEYCHAINS=()
  while IFS= read -r kc; do
    kc="${kc#"${kc%%[![:space:]]*}"}"; kc="${kc%\"}"; kc="${kc#\"}"
    [ -n "$kc" ] && ORIGINAL_KEYCHAINS+=("$kc")
  done < <(security list-keychains -d user)
  restore_keychains() { security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}"; }
  trap restore_keychains EXIT
  security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" "$SIGN_KEYCHAIN"
  security unlock-keychain -p "$(cat "$SIGN_DIR/keychain.pass")" "$SIGN_KEYCHAIN"
  codesign --force --deep --sign "$(cat "$SIGN_DIR/identity.sha1")" \
    --identifier "$BUNDLE_ID" "$OUT" >/dev/null
  restore_keychains
  trap - EXIT
  echo "  imzalandı"
else
  echo "▸ İmzalanıyor (ad-hoc)…"
  echo "  not: her derlemede kamera izni sıfırlanır; kalıcı olması için bir kez"
  echo "  ./Scripts/setup_signing.sh çalıştır"
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$OUT" 2>/dev/null \
    && echo "  imzalandı" || echo "  imza atlandı"
fi

# Launch Services'in eski sürümü hatırlamaması için kaydı tazele.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$OUT" >/dev/null 2>&1 || true

echo ""
echo "✅ Hazır: $ROOT/$OUT"

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ /Applications içine kopyalanıyor…"
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$OUT" "/Applications/${APP_NAME}.app"
  echo "✅ Kuruldu: /Applications/${APP_NAME}.app"
fi

echo ""
echo "Çalıştırmak için:  open \"$ROOT/$OUT\""
