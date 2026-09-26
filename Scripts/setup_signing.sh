#!/bin/bash
# Yerel, kendinden imzalı bir kod imzalama kimliği kurar. Bir kez çalıştırılır.
#
# Neden: ad-hoc imzada macOS uygulamayı kod özetiyle tanır; her derlemede özet
# değişir ve kamera izni düşer. Sabit bir sertifikayla imzalanınca izin kalıcı olur.
#
# Ücretsiz ve yalnız bu Mac'te geçerli. Giriş anahtar zincirine ve sistem güven
# ayarlarına dokunmaz: kimlik ayrı bir anahtar zinciri dosyasında durur.
# Geri almak için:  rm -rf "$HOME/Library/Application Support/MacGuard/signing"
set -euo pipefail

DIR="$HOME/Library/Application Support/MacGuard/signing"
KEYCHAIN="$DIR/macguard-signing.keychain-db"
NAME="MacGuard Local Signing"

if [ -f "$DIR/identity.sha1" ] && [ -f "$KEYCHAIN" ]; then
  echo "✓ İmza kimliği zaten kurulu: $(cat "$DIR/identity.sha1")"
  exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" >/dev/null 2>&1

# OpenSSL 3'ün varsayılan p12 şifrelemesini macOS okuyamıyor; eski biçim gerekiyor.
LEGACY=""
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then LEGACY="-legacy"; fi
P12_PASS="$(openssl rand -hex 16)"
openssl pkcs12 -export $LEGACY -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/id.p12" -passout "pass:$P12_PASS"

KC_PASS="$(openssl rand -hex 24)"
rm -f "$KEYCHAIN"
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security import "$WORK/id.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null
# codesign her derlemede anahtar zinciri onayı sormasın.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null

(umask 177; printf '%s' "$KC_PASS" > "$DIR/keychain.pass")
openssl x509 -in "$WORK/cert.pem" -noout -fingerprint -sha1 \
  | cut -d= -f2 | tr -d ':' > "$DIR/identity.sha1"

echo "✓ İmza kimliği kuruldu: $(cat "$DIR/identity.sha1")"
echo "  Bundan sonraki derlemeler bununla imzalanır. Kamera iznini bir kez daha vermen gerekecek."
