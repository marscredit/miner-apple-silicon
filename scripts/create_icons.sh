#!/bin/bash

# Create temporary directory for icon processing
mkdir -p temp_icons
cd temp_icons

# Download the original logo
curl -L "https://github.com/marscredit/brandassets/blob/main/marscredit_square_solid.png?raw=true" -o original.png

# Check if ImageMagick is installed
if ! command -v convert &> /dev/null; then
    echo "ImageMagick is required but not installed. Please install it first:"
    echo "brew install imagemagick"
    exit 1
fi

# Create icons in all required sizes
convert original.png -resize 16x16 ../src/MarsCredit/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_16.png
convert original.png -resize 32x32 ../src/MarsCredit/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_32.png
convert original.png -resize 64x64 ../src/MarsCredit/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_64.png
convert original.png -resize 128x128 ../src/MarsCredit/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_128.png
convert original.png -resize 256x256 ../src/MarsCredit/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_256.png
convert original.png -resize 512x512 ../src/MarsCredit/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_512.png
convert original.png -resize 1024x1024 ../src/MarsCredit/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png

# Clean up
cd ..
rm -rf temp_icons

echo "App icons have been created successfully!" 