#!/bin/bash

# Git setup script for KeyPath

echo "Setting up Git repository..."

# Initialize git repository
git init

# Create .gitignore
cat > .gitignore << 'EOF'
# Build artifacts
.build/
build/
.swiftpm/

# macOS
.DS_Store
*.swp
*.swo
*~

# Xcode
*.xcodeproj
*.xcworkspace
*.xcuserdata/

# Temporary files
*.tmp
*.temp
/tmp/

# IDE
.vscode/
.idea/

# Logs
*.log
EOF

# Set up Git user (update with your details)
git config user.name "Your Name"
git config user.email "your.email@example.com"

# Add all files
git add .

# Create initial commit
git commit -m "Initial commit: Complete KeyPath implementation

- Swift Package Manager project structure
- SwiftUI app with keyboard capture
- Kanata service management with LaunchDaemon
- Hot reload functionality
- Comprehensive test suite (13 unit tests + 4 integration tests)
- Installation and build scripts
- Complete documentation

Features:
- Simplified Karabiner-Elements inspired architecture
- System-level service management
- File-based configuration (no XPC complexity)
- Real-time config updates and service restart
- Full test coverage and validation

🤖 Generated with Claude Code"

echo "Git repository initialized!"
echo
echo "To push to GitHub:"
echo "1. Create a new repository on GitHub"
echo "2. Add the remote: git remote add origin https://github.com/yourusername/keypath.git"
echo "3. Push: git push -u origin main"