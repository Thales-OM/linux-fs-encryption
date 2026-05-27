#!/usr/bin/env bash
set -euo pipefail

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID=${ID,,}
else
    echo "❌ Не удалось определить ОС. Установите зависимости вручную."
    exit 1
fi

echo "🔍 Detected distribution: $DISTRO_ID"

case "$DISTRO_ID" in
    ubuntu|debian|linuxmint|pop|elementary|kali)
        echo "📦 Installing via apt..."
        sudo apt-get update -y
        sudo apt-get install -y libfuse3-dev libsodium-dev build-essential pkg-config
        ;;
    fedora|centos|rhel|rocky|almalinux|amzn|mageia)
        echo "📦 Installing via dnf/yum..."
        if command -v dnf &>/dev/null; then
            sudo dnf install -y fuse3-devel libsodium-devel gcc make pkgconf-pkg-config
        else
            sudo yum install -y fuse3-devel libsodium-devel gcc make pkgconfig
        fi
        ;;
    arch|manjaro|endeavouros|garuda|artix)
        echo "📦 Installing via pacman..."
        sudo pacman -Sy --noconfirm fuse3 libsodium gcc make pkgconf
        ;;
    opensuse*|sles|sle*)
        echo "📦 Installing via zypper..."
        sudo zypper --non-interactive install fuse3-devel libsodium-devel gcc make pkg-config
        ;;
    alpine)
        echo "📦 Installing via apk..."
        sudo apk add --no-cache fuse3-dev libsodium-dev gcc make pkgconfig
        ;;
    *)
        echo "❌ Unsupported distribution: $DISTRO_ID"
        echo "📋 Required packages: fuse3-devel/libfuse3-dev, libsodium-dev, gcc, make, pkg-config"
        exit 1
        ;;
esac

echo "✅ Dependencies installed successfully."