$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker was not found. Install and start Docker Desktop first."
}

Write-Host "Checking Docker engine..."
docker info | Out-Null

$apiKey = $env:ANTHROPIC_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    $apiKey = Read-Host "Enter the DeepSeek API Key"
}
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw "API Key cannot be empty."
}

$env:ANTHROPIC_API_KEY = $apiKey
$env:AI_PROVIDER = "anthropic"
$env:ANTHROPIC_BASE_URL = "https://api.deepseek.com/anthropic"
$env:ANTHROPIC_MODEL = "deepseek-v4-pro"
$env:KNOWLEDGE_VECTOR_ENABLED = "false"
$env:AGENT_FRAMEWORK = "event_driven_multi_agent"

Write-Host "Building and starting PsycheLink..."
docker compose up -d --build

Write-Host ""
Write-Host "Container status:"
docker compose ps
Write-Host ""
Write-Host "URL: http://localhost:8080"
Write-Host "Logs: docker compose logs -f app"
Read-Host "Press Enter to exit"
