#!/bin/bash
# Launch the Textual dashboard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if textual is installed
if ! python3 -c "import textual" 2>/dev/null; then
    echo "📦 Installing Textual dashboard dependencies..."
    cd "$PROJECT_ROOT/dashboard" && pip install -r requirements.txt --quiet
    cd "$PROJECT_ROOT"
fi

echo "🚀 Launching SGLang Dashboard..."
cd "$PROJECT_ROOT/dashboard" && python3 dashboard.py
