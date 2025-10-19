#!/bin/bash

# Pre-publication verification script for MnesiaEx
# Run this before publishing to Hex.pm

set -e

echo "🔍 MnesiaEx Pre-Publication Verification"
echo "========================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check functions
check_passed() {
    echo -e "${GREEN}✓${NC} $1"
}

check_failed() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

check_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# 1. Check required files exist
echo "📁 Checking required files..."
[ -f "README.md" ] && check_passed "README.md exists" || check_failed "README.md missing"
[ -f "LICENSE" ] && check_passed "LICENSE exists" || check_failed "LICENSE missing"
[ -f "CHANGELOG.md" ] && check_passed "CHANGELOG.md exists" || check_failed "CHANGELOG.md missing"
[ -f "mix.exs" ] && check_passed "mix.exs exists" || check_failed "mix.exs missing"
echo ""

# 2. Check dependencies
echo "📦 Installing dependencies..."
mix deps.get > /dev/null 2>&1
check_passed "Dependencies installed"
echo ""

# 3. Run formatter
echo "🎨 Checking code formatting..."
if mix format --check-formatted > /dev/null 2>&1; then
    check_passed "Code is properly formatted"
else
    check_warning "Code is not formatted. Run: mix format"
fi
echo ""

# 4. Compile with warnings as errors
echo "🔨 Compiling project..."
if mix compile --warnings-as-errors > /dev/null 2>&1; then
    check_passed "Project compiles without warnings"
else
    check_failed "Project has compilation warnings or errors"
fi
echo ""

# 5. Run tests
echo "🧪 Running tests..."
if mix test > /dev/null 2>&1; then
    check_passed "All tests passing"
else
    check_failed "Tests failing. Fix tests before publishing."
fi
echo ""

# 6. Generate documentation
echo "📚 Generating documentation..."
if mix docs > /dev/null 2>&1; then
    check_passed "Documentation generated successfully"
else
    check_warning "Documentation generation had warnings"
fi
echo ""

# 7. Check version
echo "🏷️  Checking version..."
VERSION=$(grep '@version' mix.exs | cut -d'"' -f2)
echo "   Current version: $VERSION"
if [[ $VERSION == "1.0.0" ]]; then
    check_passed "Version is set for release"
else
    check_warning "Version is $VERSION (expected 1.0.0)"
fi
echo ""

# 8. Build Hex package
echo "📦 Building Hex package..."
if mix hex.build > /dev/null 2>&1; then
    check_passed "Hex package builds successfully"
    
    # Show package info
    echo ""
    echo "Package details:"
    echo "   Name: mnesia_ex"
    echo "   Version: $VERSION"
    echo "   Files: $(ls -1 mnesia_ex-*.tar 2>/dev/null | wc -l) tarball(s)"
else
    check_failed "Hex package build failed"
fi
echo ""

# 9. Check Git status
echo "📝 Checking Git status..."
if [ -z "$(git status --porcelain)" ]; then
    check_passed "Working directory is clean"
else
    check_warning "Uncommitted changes exist. Commit before publishing."
    git status --short
fi
echo ""

# 10. Check for version tag
echo "🏷️  Checking Git tags..."
if git tag | grep -q "^v${VERSION}$"; then
    check_passed "Version tag v$VERSION exists"
else
    check_warning "Version tag v$VERSION not found. Create with: git tag -a v$VERSION -m 'Release v$VERSION'"
fi
echo ""

# Summary
echo "========================================"
echo -e "${GREEN}✅ Pre-publication checks complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Review CHANGELOG.md"
echo "2. git commit -am 'Release v$VERSION'"
echo "3. git tag -a v$VERSION -m 'Release v$VERSION'"
echo "4. git push origin master && git push origin v$VERSION"
echo "5. mix hex.publish"
echo "6. Create GitHub release"
echo ""
echo "🚀 Ready to publish!"

