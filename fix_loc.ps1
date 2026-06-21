# Fix localization.dart - Part 1: Read part1 and fix truncated line
$part1 = "c:\Users\DELL\Sectop\frontend\lib\core\localization_part1.dart"
$out = "c:\Users\DELL\Sectop\frontend\lib\core\localization.dart"

# Read part1
$content = Get-Content $part1 -Encoding UTF8 -Raw

# Fix the truncated line
$content = $content -replace "'please_enter_phone': 'Jọwọ t", "'please_enter_phone': 'Jọwọ tẹ nọmba foonu rẹ sii',"

# Write the fixed content
Set-Content -Path $out -Value $content -Encoding UTF8

Write-Host "Part1 written. Size: $((Get-Item $out).Length)"
