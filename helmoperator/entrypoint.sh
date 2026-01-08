#!/bin/bash
set -e

# Auto-install Helm if not present
if ! command -v helm &> /dev/null; then
    echo "⚙️  helm not found. Installing..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "✅ helm installed successfully!"
else
    echo "✅ helm already installed: $(helm version --short)"
fi

# Auto-install operator-sdk if not present
if ! command -v operator-sdk &> /dev/null; then
    echo "⚙️  operator-sdk not found. Installing..."
    ARCH=amd64
    OS=linux
    VER=v1.39.1
    curl -sLO "https://github.com/operator-framework/operator-sdk/releases/download/${VER}/operator-sdk_${OS}_${ARCH}"
    chmod +x operator-sdk_${OS}_${ARCH}
    mv operator-sdk_${OS}_${ARCH} /usr/local/bin/operator-sdk
    echo "✅ operator-sdk ${VER} installed successfully!"
else
    echo "✅ operator-sdk already installed: $(operator-sdk version | head -1)"
fi

# Execute the passed command or start bash
exec "${@:-bash}"
