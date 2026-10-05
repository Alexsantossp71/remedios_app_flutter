#!/bin/bash
# Script to run E2E tests with Playwright

echo "🧪 Remedios App - E2E Tests with Playwright"
echo ""

# Check if Flutter is running
if ! curl -s http://localhost:5000 > /dev/null 2>&1; then
    echo "❌ Flutter web server not running on port 5000"
    echo ""
    echo "Please run in another terminal:"
    echo "  cd ../  "
    echo "  flutter run -d web-server --web-port=5000"
    echo ""
    exit 1
fi

echo "✅ Flutter web server detected on port 5000"
echo ""

# Run Playwright tests
echo "🚀 Running Playwright tests..."
echo ""

npx playwright test "$@"

echo ""
echo "📊 To view the report:"
echo "  npm run report"
