$registry = "netiksstoreregistry"

# 1. Ask the user for the number of days
$daysInput = Read-Host "Enter the number of days to KEEP images (e.g., 20). Images older than this will be deleted"

# 2. Validate the input (default to 20 if left blank, or check if it's a valid number)
if ([string]::IsNullOrWhiteSpace($daysInput)) {
    $days = 20
    Write-Host "ℹ️ No input provided. Defaulting to 20 days." -ForegroundColor Cyan
} elseif ($daysInput -match '^\d+$') {
    $days = [int]$daysInput
} else {
    Write-Host "❌ Invalid input. Please enter a valid number (e.g., 20)." -ForegroundColor Red
    exit
}

Write-Host "🔍 Running DRY RUN to see what images older than $days days will be deleted..." -ForegroundColor Yellow
Write-Host "---------------------------------------------------------"

# 3. Run the dry-run with the dynamic $days variable
az acr run --registry $registry --cmd "acr purge --filter '.*:.*' --ago ${days}d --untagged --dry-run" /dev/null

Write-Host "---------------------------------------------------------"

# 4. Ask for final confirmation
$confirmation = Read-Host "❓ Does this look correct? Proceed with ACTUAL deletion? (y/n)"

if ($confirmation -eq 'y' -or $confirmation -eq 'Y') {
    Write-Host "🗑️ Running actual purge for images older than $days days..." -ForegroundColor Green
    az acr run --registry $registry --cmd "acr purge --filter '.*:.*' --ago ${days}d --untagged" /dev/null
    Write-Host "✅ Purge complete!" -ForegroundColor Green
} else {
    Write-Host "❌ Aborted. No images were deleted." -ForegroundColor Red
}