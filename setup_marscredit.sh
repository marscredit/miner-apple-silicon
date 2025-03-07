#!/bin/bash

# Exit on error
set -e

echo "Setting up go-marscredit..."

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "Error: Go is not installed. Please install Go first."
    exit 1
fi

# Create marscredit directory if it doesn't exist
MARSCREDIT_DIR="$HOME/.marscredit"
mkdir -p "$MARSCREDIT_DIR"

# Clone go-marscredit if it doesn't exist
if [ ! -d "$MARSCREDIT_DIR/go-marscredit" ]; then
    echo "Cloning go-marscredit..."
    git clone https://github.com/marscredit/go-marscredit.git "$MARSCREDIT_DIR/go-marscredit"
fi

# Build go-marscredit
cd "$MARSCREDIT_DIR/go-marscredit"
echo "Building go-marscredit..."
make geth

# Create symbolic link to the binary
echo "Creating symbolic link..."
ln -sf "$MARSCREDIT_DIR/go-marscredit/build/bin/geth" "$MARSCREDIT_DIR/marscredit"

echo "Setup complete! go-marscredit binary is available at $MARSCREDIT_DIR/marscredit" 