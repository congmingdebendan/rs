#!/bin/bash
# RustDesk 服务端工具部署脚本
#
# 作用：从 GitHub 拉取最新的运维脚本，安装到 /opt/rustdesk/tools/
# 原则：
#   1. 先下载到临时目录，校验通过才替换正式文件，下载失败绝不破坏现有版本
#   2. 替换前自动备份，出问题可一键回滚
#   3. 只新增 tools/ 目录，不触碰 /opt/rustdesk/ 下任何现有文件
#   4. 不安装任何软件、不重启任何服务
#
# 用法：bash /opt/rustdesk/tools/deploy.sh

set -u

REPO_RAW="https://raw.githubusercontent.com/congmingdebendan/rs/master/deploy"
INSTALL_DIR="/opt/rustdesk/tools"
BACKUP_DIR="${INSTALL_DIR}/backup"

# 需要部署的脚本清单，以后新增脚本在这里加一行即可
FILES="status.sh deploy.sh"

echo "=========================================="
echo " RustDesk 工具部署"
echo " 时间：$(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo

# ---------- 准备临时目录 ----------
# 临时目录必须与安装目录同分区，这样后面 mv 才是原子操作（见第 3 步说明）
mkdir -p "$INSTALL_DIR" || { echo "❌ 无法创建 ${INSTALL_DIR}"; exit 1; }
TMP_DIR=$(mktemp -d "${INSTALL_DIR}/.tmp.XXXXXX") || { echo "❌ 无法创建临时目录"; exit 1; }
# 无论成功失败都清理临时目录
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------- 1. 下载 ----------
echo "【1/4】从 GitHub 下载最新脚本"
for f in $FILES; do
    printf "  下载 %-12s " "$f"
    if curl -fsSL --connect-timeout 10 --max-time 60 \
            -o "${TMP_DIR}/${f}" "${REPO_RAW}/${f}" 2>/dev/null; then
        echo "✅"
    else
        echo "❌ 失败"
        echo
        echo "下载失败，已中止。现有文件未做任何改动。"
        echo "请检查服务器能否访问 GitHub：curl -sI https://raw.githubusercontent.com"
        exit 1
    fi
done
echo

# ---------- 2. 校验 ----------
# 防止拉到空文件或被污染的内容后覆盖掉可用版本
echo "【2/4】校验文件"
for f in $FILES; do
    printf "  校验 %-12s " "$f"
    if [ ! -s "${TMP_DIR}/${f}" ]; then
        echo "❌ 文件为空"
        echo
        echo "校验失败，已中止。现有文件未做任何改动。"
        exit 1
    fi
    # bash -n 只做语法检查，不会执行脚本内容
    if ! bash -n "${TMP_DIR}/${f}" 2>/dev/null; then
        echo "❌ 语法错误"
        echo
        echo "校验失败，已中止。现有文件未做任何改动。"
        exit 1
    fi
    echo "✅"
done
echo

# ---------- 3. 备份并安装 ----------
echo "【3/4】备份并安装"
mkdir -p "$BACKUP_DIR"
STAMP=$(date '+%Y%m%d-%H%M%S')

for f in $FILES; do
    if [ -f "${INSTALL_DIR}/${f}" ]; then
        # 内容一致就跳过，避免产生无意义的备份
        if cmp -s "${INSTALL_DIR}/${f}" "${TMP_DIR}/${f}"; then
            echo "  $f 无变化，跳过"
            continue
        fi
        cp -p "${INSTALL_DIR}/${f}" "${BACKUP_DIR}/${f}.${STAMP}"
        echo "  $f 已备份 → backup/${f}.${STAMP}"
    fi
    # 用 mv 而不是 cp：mv 在同分区是原子的 rename，会生成新 inode。
    # deploy.sh 更新自己时，正在执行的 bash 仍持有旧 inode 继续读原内容，
    # 不会因文件被中途覆盖而读到错乱的指令。
    chmod +x "${TMP_DIR}/${f}"
    mv -f "${TMP_DIR}/${f}" "${INSTALL_DIR}/${f}"
    echo "  $f 已更新 ✅"
done

# 备份目录只保留最近 20 份，避免长期累积占用空间
ls -1t "${BACKUP_DIR}" 2>/dev/null | tail -n +21 | while read -r old; do
    rm -f "${BACKUP_DIR}/${old}"
done
echo

# ---------- 4. 完成 ----------
echo "【4/4】完成"
echo
echo "  安装位置：${INSTALL_DIR}"
echo "  运行检查：bash ${INSTALL_DIR}/status.sh"
echo "  再次更新：bash ${INSTALL_DIR}/deploy.sh"
if [ -d "$BACKUP_DIR" ] && [ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
    echo "  回滚方式：cp ${BACKUP_DIR}/<文件名.时间戳> ${INSTALL_DIR}/<文件名>"
fi
echo
echo "=========================================="
echo " 本次未安装任何软件，未重启任何服务"
echo "=========================================="
