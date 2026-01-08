#!/bin/bash
set -e

echo "🔧 Checking development environment..."

# Auto-install Ansible if not present
if ! command -v ansible &> /dev/null; then
    echo "⚙️  ansible not found. Installing..."
    pip install --quiet ansible ansible-runner ansible-runner-http openshift kubernetes jmespath
    echo "✅ ansible installed successfully!"
else
    echo "✅ ansible already installed: $(ansible --version | head -1)"
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

# Auto-install make if not present
if ! command -v make &> /dev/null; then
    echo "⚙️  make not found. Installing..."
    apt-get update -qq && apt-get install -y -qq make > /dev/null
    echo "✅ make installed successfully!"
else
    echo "✅ make already installed"
fi

echo "🚀 Environment ready!"
echo ""

# Execute the passed command or start bash
exec "${@:-bash}"
