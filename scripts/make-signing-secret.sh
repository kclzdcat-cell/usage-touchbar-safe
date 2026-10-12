#!/usr/bin/env bash
#
# 生成一张只给 Usage Touch Bar 用的固定签名证书，并把它复制到剪贴板，
# 用来粘贴到 GitHub 仓库的 Secrets 里（名字填 SIGNING_P12）。
#
# 为什么需要：macOS 的钥匙串是按"签名身份"记住「始终允许」的。没有固定证书时，
# 每次编译的签名都不一样，每次更新都要重新输入密码授权。有了固定证书，
# 选一次「始终允许」，以后更新都不会再问。
#
# 安全说明：
# - 证书只用来给这个 App 签名，不会导入你电脑的钥匙串，生成后临时文件立即删除。
# - 私钥只存在于 GitHub 的加密 Secrets 里（公开仓库也看不到），不会进代码仓库。
# - 不要把剪贴板里的内容发给任何人。
#
# 用法：bash scripts/make-signing-secret.sh
set -euo pipefail

# 必须用系统自带的 LibreSSL（/usr/bin/openssl），它导出的 .p12 才能被 macOS 正常导入
OPENSSL=/usr/bin/openssl
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = UsageTouchBar Signing
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" >/dev/null 2>&1
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "UsageTouchBar Signing" -out "$TMP/signing.p12" -passout pass:usagetouchbar >/dev/null 2>&1

base64 < "$TMP/signing.p12" | tr -d '\n' | pbcopy

echo "✓ 已生成签名证书，并复制到剪贴板。"
echo
echo "接下来："
echo "  1. 打开 https://github.com/kclzdcat-cell/usage-touchbar-safe/settings/secrets/actions/new"
echo "  2. Name 填：SIGNING_P12"
echo "  3. Secret 里粘贴（⌘V），点 Add secret"
echo "  4. 到 Actions 页面重新运行一次 Build DMG（或推送任何改动）"
echo
echo "证书指纹（以后核对用）："
"$OPENSSL" x509 -in "$TMP/cert.pem" -noout -fingerprint -sha256
