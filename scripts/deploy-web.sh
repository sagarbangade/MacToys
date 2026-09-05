#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
WEB_APP_DIR="$ROOT_DIR/WebApps/mobile-scanner"
PUBLIC_REPO="/tmp/mactoys-mobile-scanner"

echo "Building Mobile Scanner web app..."
cd "$WEB_APP_DIR"
npm run build

echo "Deploying to public GitHub Pages repo..."
# Clone or update the public repo
if [ -d "$PUBLIC_REPO" ]; then
    cd "$PUBLIC_REPO"
    git pull origin main
else
    cd /tmp
    gh repo clone sagarbangade/mactoys-mobile-scanner
    cd "$PUBLIC_REPO"
fi

# Clear old files and copy new build
find . -maxdepth 1 ! -name '.git' ! -name '.' -exec rm -rf {} +
cp -R "$WEB_APP_DIR/dist/"* .

# Commit and push
git add -A
git commit -m "Deploy: $(date '+%Y-%m-%d %H:%M:%S')" || echo "No changes to deploy"
git push origin main

echo "✅ Deployed to https://sagarbangade.github.io/mactoys-mobile-scanner/"
