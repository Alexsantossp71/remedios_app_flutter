# Script to run E2E tests with Playwright on Windows
# Usage: .\run-tests.ps1

Write-Host "🧪 Remedios App - E2E Tests with Playwright" -ForegroundColor Cyan
Write-Host ""

# Check if Flutter is running
try {
    $response = Invoke-WebRequest -Uri "http://localhost:5000" -TimeoutSec 2 -UseBasicParsing -ErrorAction SilentlyContinue
    Write-Host "✅ Flutter web server detected on port 5000" -ForegroundColor Green
} catch {
    Write-Host "❌ Flutter web server not running on port 5000" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please run in another terminal:" -ForegroundColor Yellow
    Write-Host "  cd .." -ForegroundColor White
    Write-Host "  flutter run -d web-server --web-port=5000" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "🚀 Running Playwright tests..." -ForegroundColor Cyan
Write-Host ""

# Run Playwright tests
npm run test

Write-Host ""
Write-Host "📊 To view the report:" -ForegroundColor Cyan
Write-Host "  npm run report" -ForegroundColor White
