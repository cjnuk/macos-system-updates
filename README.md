# macOS System Updates Script

An elegant, comprehensive system update script for macOS that keeps all your development tools, packages, and applications up to date in one beautiful command.

## ✨ Features

- **🚀 One Command Updates**: Updates everything in your macOS development environment
- **🎨 Beautiful Output**: Clear visual status indicators with emoji categories
- **🔍 Dry Run Mode**: Preview what would be updated without making changes
- **📊 Coverage Audit**: See what this script covers vs. other update mechanisms
- **📱 Unmanaged Apps**: List applications not managed by this script (by category)
- **⚡ Intelligent Skipping**: Skip specific update categories as needed
- **📝 Comprehensive Logging**: All operations logged to file
- **🛡️ Safe Execution**: Guard against double-execution and proper error handling

## 🛠️ What It Updates

### Core System
- **macOS Software Updates** - System and security updates
- **Oh My Zsh** - Shell framework updates

### Package Managers
- **Homebrew** - Packages, casks, and cleanup
- **Conda** - Base environment and all packages
- **Mac App Store** - Apps via `mas` CLI

### Development Tools
- **Node Version Manager (NVM)** - Latest version with backup
- **UV Python Package Manager** - Self-update
- **NPM Global Packages** - Claude Code and Gemini CLI

## 📋 Requirements

### Required
- macOS with `softwareupdate` (built-in)
- [Homebrew](https://brew.sh)
- [Conda](https://docs.conda.io/en/latest/miniconda.html) (Anaconda/Miniconda)

### Optional (will be skipped if not installed)
- [Oh My Zsh](https://ohmyz.sh) - Shell framework updates
- [Mac App Store CLI (mas)](https://github.com/mas-cli/mas) - `brew install mas` for App Store updates
- [Node Version Manager (nvm)](https://github.com/nvm-sh/nvm) - Node.js version management
- [UV Python Package Manager](https://github.com/astral-sh/uv) - Modern Python package manager
- [Node Package Manager (npm)](https://nodejs.org) - Global package updates

💡 **Smart Skipping**: The script automatically detects which tools are installed and gracefully skips missing ones with clear status messages.

## 🚀 Installation

1. **Download the script:**
   ```bash
   curl -O https://raw.githubusercontent.com/CJNUK/macos-system-updates/main/brew_and_conda_update.sh
   ```

2. **Make it executable:**
   ```bash
   chmod +x brew_and_conda_update.sh
   ```

3. **Run it:**
   ```bash
   ./brew_and_conda_update.sh
   ```

### 🔗 Creating a Global Shortcut (Optional)

For convenience, you can create a shortcut to run the script from anywhere in your terminal:

1. **Move the script to a permanent location:**
   ```bash
   sudo mkdir -p /usr/local/bin
   sudo cp brew_and_conda_update.sh /usr/local/bin/
   ```

2. **Create a shorter command alias:**
   ```bash
   sudo ln -sf /usr/local/bin/brew_and_conda_update.sh /usr/local/bin/sysupdate
   ```

3. **Now you can run from anywhere:**
   ```bash
   # From any directory:
   sysupdate
   sysupdate --dry-run
   sysupdate --list-unmanaged
   ```

**Alternative: Shell Alias Method**
Add this to your `~/.zshrc` or `~/.bashrc`:
```bash
alias sysupdate='/path/to/brew_and_conda_update.sh'
```
Then reload your shell: `source ~/.zshrc`

## 💡 Usage Examples

### Basic Usage
```bash
# Update everything
./brew_and_conda_update.sh

# Preview what would be updated (no changes made)
./brew_and_conda_update.sh --dry-run

# Show detailed technical output
./brew_and_conda_update.sh --verbose
```

### Advanced Usage
```bash
# Skip macOS and App Store updates
./brew_and_conda_update.sh --skip macos,appstore

# Skip shell framework and Node.js updates
./brew_and_conda_update.sh --skip zsh,node

# See what this script covers vs. other tools
./brew_and_conda_update.sh --audit

# List apps not managed by this script
./brew_and_conda_update.sh --list-unmanaged

# Show unmanaged apps with last modified dates
./brew_and_conda_update.sh --list-unmanaged --verbose
```

### 💡 Pro Tips

**Duplicate App Detection**: Verbose mode may reveal duplicate app versions (e.g., "Adobe Premiere Pro 2024" and "Adobe Premiere Pro 2025"). The oldest-first sorting helps identify cleanup opportunities where you can remove outdated versions to free up disk space.

**Update Priority**: Apps with older modification dates (shown first in verbose mode) are more likely to need updates, making it easy to prioritize manual update checks.

## 📖 Command Line Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-n, --dry-run` | Preview updates without making changes |
| `-a, --audit` | Show what this script covers vs. other update mechanisms |
| `-l, --list-unmanaged` | List apps not managed by this script (by category) |
| `-s, --skip CATEGORIES` | Skip specific updates (comma-separated) |
| `-v, --verbose` | Enable verbose output (includes dates with --list-unmanaged) |

### Skip Categories
- `macos` - macOS software updates
- `zsh` - Oh My Zsh updates
- `brew` - Homebrew packages and apps
- `conda` - Conda environment updates
- `appstore` - Mac App Store apps
- `node` - Node Version Manager updates
- `uv` - UV Python package manager
- `npm` - NPM global packages

## 📊 Sample Output

```
✨ ────────────────────────────────────────────────────────────────────────────────

🚀 System Update Session
   Refreshing your development environment

✨ ────────────────────────────────────────────────────────────────────────────────

🍎 macOS Updates          ✅ No updates available
🐚 Oh My Zsh               ⬆️  Updated to latest version
🍺 Homebrew packages       ⬆️  3 packages updated
🐍 Conda packages          ⬆️  7 packages updated
📱 App Store apps          ✅ No updates available
🟢 Node Version Manager    ✅ Already latest (v0.39.3)
🐍 UV Package Manager      ✅ Already latest
📦 NPM Global packages     ✅ All packages current

✨ ────────────────────────────────────────────────────────────────────────────────

🎉 Update Session Complete!
   Updated 4 categories in 2m 34s
   📝 Full log: /path/to/brew_conda_update.log

✨ ────────────────────────────────────────────────────────────────────────────────
```

## 📁 Logging

All operations are logged to `brew_conda_update.log` in the script directory. The log includes:
- Timestamp and execution mode
- Detailed command output
- Error messages and warnings
- Summary of changes made

## 🔒 Safety Features

- **Guard Against Double Execution**: Prevents running multiple instances
- **Dry Run Mode**: Preview changes before applying
- **Backup Creation**: NVM installations are backed up before updates
- **Error Handling**: Graceful handling of missing dependencies
- **Verbose Logging**: Optional detailed output for troubleshooting

## 🗂️ Unmanaged Applications

The `--list-unmanaged` feature categorizes applications not managed by this script:

- 🎨 **Adobe Creative Suite** - Photoshop, Illustrator, etc.
- 🏢 **Microsoft Office** - Word, Excel, PowerPoint, etc.
- 🎵 **Professional Audio** - Logic Pro, GarageBand, audio plugins
- 🔧 **Hardware Utilities** - Focusrite, Loupedeck, etc.
- 💼 **Business Tools** - Carbon Copy Cloner, CleanMyMac, etc.
- 🧑‍💻 **Development Tools** - JetBrains IDEs, Xcode, etc.
- 📱 **Media & Content** - Kindle, streaming apps, etc.
- 🎯 **Productivity** - Task managers, note-taking apps, etc.
- 🌐 **Browsers** - Arc, Firefox, Chrome
- 🔒 **Security** - VPN clients, password managers
- 🎮 **Entertainment** - Steam, games, communication apps

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📝 Author

Created by Chris Norris