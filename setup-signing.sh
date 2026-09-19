#!/bin/bash
# 创建本机自签代码签名证书。
#
# 为什么要这一步：
#   辅助功能（Accessibility）权限是绑定到「代码签名」的。
#   如果用 ad-hoc 签名（codesign -s -），签名的 designated requirement 是
#   **二进制哈希**，每次重新编译哈希都变，macOS 会把它当成一个全新应用，
#   于是每次构建后都要重新授权一次 —— 非常烦。
#
#   换成固定证书后，requirement 变成
#     identifier "..." and certificate root = H"<证书哈希>"
#   绑定的是证书而不是二进制，重建后授权依然有效（只需授权一次）。
#
# 这个脚本只在本机创建并信任证书，不会上传任何东西。
# 运行一次即可；之后 build.sh 会自动检测并使用它。

set -euo pipefail

CERT_CN="WinKey Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo "WinKey 自签证书设置"
echo "===================="

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_CN"; then
    echo "✅ 已存在证书「$CERT_CN」，无需重复创建。"
    security find-identity -v -p codesigning | grep "$CERT_CN" | sed 's/^/   /'
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

echo "==> 生成自签证书"
cat > openssl.cnf <<'EOF'
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_codesign
prompt = no

[ req_distinguished_name ]
CN = WinKey Local Signing
O  = WinKey
C  = CN

[ v3_codesign ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout winkey.key -out winkey.crt \
    -days 3650 -config openssl.cnf 2>/dev/null

openssl pkcs12 -export -out winkey.p12 \
    -inkey winkey.key -in winkey.crt \
    -passout pass:winkey -name "$CERT_CN" 2>/dev/null

echo "==> 导入登录钥匙串"
security import winkey.p12 -k "$KEYCHAIN" -P winkey \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "==> 设为代码签名受信任"
# 这一步可能弹出系统密码提示，属正常
security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" winkey.crt

echo
if security find-identity -v -p codesigning | grep -q "$CERT_CN"; then
    echo "✅ 完成。build.sh 之后会自动使用该证书签名。"
    security find-identity -v -p codesigning | grep "$CERT_CN" | sed 's/^/   /'
else
    echo "⚠️  证书已导入但未被识别为有效签名身份。"
    echo "   可打开「钥匙串访问」确认「$CERT_CN」存在且信任设置为「代码签名：始终信任」。"
fi
