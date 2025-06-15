# Mars Credit Miner - Development Archive

This `.cursor` directory contains all development history, archived files, and collaborative development data organized by category.

## 📁 Directory Structure

### 🔧 `/fix/` - Shell Scripts & Development Tools
Contains all shell scripts used for debugging, building, and testing throughout development:
- `debug_*.sh` - Various debugging scripts for different scenarios
- `build_*.sh` - Legacy build scripts (superseded by main scripts/ directory)
- `test_*.sh` - Testing and workflow scripts
- `run_geth_in_app.sh` - Deprecated geth wrapper script

### 📚 `/readme/` - Historical Documentation
Development documentation files from various stages:
- `README.apple_silicon_optimization.md` - Apple Silicon optimization notes
- `README.fixed.md` - Bug fixes documentation  
- `README.issues.md` - Known issues and troubleshooting guide

### 🚀 `/releases/` - Development Release History
Organized by build number for development reference:

#### `/releases/build27/`
- Original Build 27 and updated version
- Contains app bundle directories for reference

#### `/releases/build28/`  
- Build 28 with new icon implementation

#### `/releases/build29/`
- Latest build with sleep/wake crash fixes

#### `/releases/misc/`
- Early unnamed builds and development DMGs

### 🗂️ `/misc/` - Legacy Components
Miscellaneous development files and legacy components:
- Old app bundles for comparison
- Configuration scripts and utilities
- Development artifacts and temporary files

## 🎯 Current Project Structure

The main project directory now contains:

```
miner-apple-silicon/
├── releases/              # All DMG files for distribution
├── builds/               # Current build outputs
├── scripts/              # Active build scripts
├── Sources/              # Swift source code
├── Resources/            # App resources
├── create_app.sh         # Main app creation script
├── README.md            # Main project documentation
└── .cursor/             # This development archive
    ├── fix/             # Legacy scripts
    ├── readme/          # Historical docs
    ├── releases/        # Development release history
    └── misc/            # Other development files
```

## 📦 Main Releases Folder

The `/releases/` folder in the project root contains all distribution-ready DMG files:
- `Mars-Credit-Miner-Build29.dmg` - **Latest** (16MB) - Sleep/wake fixes
- `Mars-Credit-Miner-Build28-With-Icon.dmg` - (77MB) - Icon implementation  
- `Mars-Credit-Miner-Build27*.dmg` - (19MB each) - Earlier builds
- `Mars Credit Miner.dmg` - (5MB) - Early build
- `rw.42085.Mars Credit Miner.dmg` - (77MB) - Development build

## 🔍 Development Workflow

This archive structure supports:
- **Version Tracking**: Complete history of all builds and approaches
- **Bug Reference**: Historical context for debugging and fixes
- **Script Library**: All development tools and utilities preserved
- **Collaborative Development**: Shared development history and decisions
- **Clean Distribution**: Main releases folder for easy access to all builds

## 📋 Active vs Archive

**Active Files** (main directory):
- Current source code and build system
- Latest build outputs
- Distribution-ready releases

**Archive Files** (this .cursor directory):
- Development history and legacy approaches
- Historical documentation and debugging scripts
- Reference implementations and experiments

---

*Development archive maintained for Mars Credit Miner collaborative development* 