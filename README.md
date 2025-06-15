# Mars Credit Miner - Apple Silicon

A native macOS cryptocurrency miner for Mars Credit, optimized for Apple Silicon (M1/M2/M3) processors.

## 🚀 Latest Updates - Build 29

### 🔧 Major Improvements
- **Fixed Sleep/Wake Crash Issue**: App now properly detects when your Mac goes to sleep and automatically stops the geth process to prevent crashes
- **Background Thread Initialization**: Heavy operations like geth binary setup now run on background threads, preventing UI freezes
- **Enhanced Process Management**: Better cleanup of geth processes when the app terminates
- **Improved Error Recovery**: More robust handling of bundled geth binary failures with graceful fallbacks
- **Organized Project Structure**: Cleaned up project files with proper organization

### 🏗️ New Project Structure
```
miner-apple-silicon/
├── Sources/                 # Swift source code
├── Resources/              # App resources (geth, icons, etc.)
├── scripts/               # Build and utility scripts
├── builds/                # Build outputs (Build 29, etc.)
├── archive/              # Old files and deprecated scripts
├── create_app.sh         # Main app bundle creation script
└── README.md            # This file
```

## 📋 Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon Mac (M1, M2, M3, or newer)
- Xcode Command Line Tools
- Swift 5.9+

## 🛠️ Quick Build Instructions

### Option 1: Automated Build (Recommended)
```bash
# Build everything with one command
./scripts/build_all.sh
```

### Option 2: Manual Build Steps
```bash
# 1. Build the Swift project
swift build -c release

# 2. Create the app bundle
./create_app.sh

# 3. (Optional) Create DMG
./scripts/build_app_dmg.sh
```

## 📱 Installation

1. Download the latest DMG from the `builds/` directory
2. Mount the DMG file
3. Drag "Mars Credit Miner.app" to your Applications folder
4. Launch the app

**Note**: You may need to right-click and select "Open" the first time due to macOS security settings.

## 🔍 Features

- **Native Apple Silicon Support**: Optimized for M1/M2/M3 processors
- **Bundled Geth Binary**: No need to install geth separately
- **Sleep/Wake Detection**: Automatically manages geth processes during system sleep
- **Background Processing**: Non-blocking initialization for smooth user experience
- **Automatic Failover**: Falls back to remote RPC if local geth fails
- **Mining Dashboard**: Real-time mining statistics and controls

## ⚙️ Configuration

The app automatically configures optimal settings for Apple Silicon Macs:

- **Cache Size**: 512MB (reduced from default 2048MB)
- **Max Peers**: 10 (reduced from default 50)
- **Sync Mode**: Full (required for mining)
- **Data Directory**: `~/.marscredit/`

## 🐛 Troubleshooting

### App Crashes When Mac Goes to Sleep
This issue is **fixed in Build 29**. The app now automatically detects sleep events and stops geth processes.

### App Freezes on Startup
This issue is **fixed in Build 29**. Heavy initialization operations now run on background threads.

### Geth Binary Issues
Build 29 includes improved error recovery:
1. Uses bundled geth binary first
2. Falls back to remote RPC if local geth fails
3. Better verification and cleanup of corrupted binaries

### General Troubleshooting
1. Check logs in `~/.marscredit/logs/`
2. Ensure you have sufficient disk space (>5GB recommended)
3. Restart the app if you encounter issues
4. For persistent issues, delete `~/.marscredit/` and restart

## 📈 Mining Performance

Optimized settings for Apple Silicon:
- **M1 Macs**: ~2-5 MH/s
- **M2 Macs**: ~3-7 MH/s  
- **M3 Macs**: ~4-9 MH/s

*Performance varies based on system load and cooling*

## 🔒 Security

- App is ad-hoc signed for security
- All network connections use HTTPS where possible
- Private keys stored in secure keychain
- No telemetry or data collection

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on Apple Silicon
5. Submit a pull request

## 📄 File Structure Details

### Core Files
- `Sources/MarsCredit/App.swift` - Main application entry point
- `Sources/MarsCredit/MiningService.swift` - Mining logic and geth management
- `create_app.sh` - Creates the macOS app bundle

### Build Scripts
- `scripts/build_all.sh` - Complete build automation
- `scripts/build_app_dmg.sh` - Creates DMG distribution file
- `scripts/app_helper.sh` - Runtime environment setup

### Resources
- `Resources/geth/geth` - Bundled geth binary (33MB)
- `Resources/mars_credit_genesis.json` - Genesis block configuration
- `Resources/gunshipboldital.otf` - Custom font

## 🗂️ Build Outputs

All builds are stored in the `builds/` directory:
- `builds/build29/` - Latest build directory
- Each build includes version info and change notes

## 📝 Release Notes

### Build 29
- Fixed sleep/wake crash issue
- Background thread initialization
- Enhanced process management
- Improved error recovery
- Organized project structure

### Previous Builds
See `archive/` directory for historical build information.

## 📞 Support

For issues and questions:
1. Check the troubleshooting section above
2. Review logs in `~/.marscredit/logs/`
3. Create an issue in the repository

## ⚖️ License

MIT License - see LICENSE file for details.

---

**Built with ❤️ for the Mars Credit community**
