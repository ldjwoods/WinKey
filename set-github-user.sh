#!/bin/bash
# 把 README / workflow 里的占位用户名替换成你的 GitHub 用户名。
#
# 用法: ./set-github-user.sh <你的用户名>
# 例:   ./set-github-user.sh ldj

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "用法: $0 <github-username>"
    exit 1
fi

USERNAME="$1"
cd "$(dirname "$0")"

# 需要替换的文件
FILES=(README.md .github/workflows/ci.yml .github/workflows/release.yml)

echo "将 <your-username> / <你的用户名> 替换为 '$USERNAME'："

changed=0
for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    # grep -c 无匹配时退出码为 1，且某些实现会输出 "0\n0" 之类的多行，
    # 直接参与整数比较会报错。这里取首行并兜底为 0。
    before=$(grep -c "your-username\|你的用户名" "$f" 2>/dev/null | head -1 || true)
    before=$(echo "${before:-0}" | tr -dc '0-9')
    before=${before:-0}
    if [ "$before" -gt 0 ]; then
        sed -i '' "s|<your-username>|$USERNAME|g; s|<你的用户名>|$USERNAME|g" "$f"
        echo "  ✅ $f （$before 处）"
        changed=$((changed + before))
    fi
done

if [ "$changed" -eq 0 ]; then
    echo "  没有找到占位符，可能已经替换过了。"
else
    echo
    echo "共替换 $changed 处。"
fi

echo
echo "剩余的占位符检查："
if grep -rn "your-username\|你的用户名" README.md .github/ 2>/dev/null; then
    echo "  ⚠️ 上面还有未替换的占位符"
else
    echo "  ✅ 已全部替换"
fi
