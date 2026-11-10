# Regenerates every card SVG from the CARDS and CONTACT blocks in tools/cards.html
# Usage:  powershell -ExecutionPolicy Bypass -File tools/generate-cards.ps1

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$page = Join-Path $PSScriptRoot "cards.html"
$tmp  = Join-Path $PSScriptRoot "_dom.html"
$err  = Join-Path $PSScriptRoot "_dom.err"

$browser = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $browser) { throw "No Chrome or Edge found. Edit the path list in this script." }

$uri = ([System.Uri]$page).AbsoluteUri
Write-Output "Rendering  $uri"
Write-Output "Using      $browser"

# stdout must be redirected to a file: chrome is a GUI-subsystem binary and a plain
# PowerShell pipe returns nothing when a normal browser session is already running.
$args = @("--headless=new", "--disable-gpu", "--virtual-time-budget=20000", "--dump-dom", $uri)
$proc = Start-Process -FilePath $browser -ArgumentList $args -RedirectStandardOutput $tmp `
                      -RedirectStandardError $err -NoNewWindow -Wait -PassThru

if (-not (Test-Path -LiteralPath $tmp)) { throw "Browser produced no output file (exit $($proc.ExitCode))." }
$dom = Get-Content -LiteralPath $tmp -Raw
Remove-Item -LiteralPath $tmp, $err -Force -ErrorAction SilentlyContinue

if ([string]::IsNullOrWhiteSpace($dom)) { throw "Empty DOM dump (exit $($proc.ExitCode))." }

$m = [regex]::Match($dom, '<pre id="out">(.*?)</pre>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $m.Success) { throw "No output block found. The page likely threw a JS error." }

$json = $m.Groups[1].Value.Trim()
if ($json -eq "PENDING" -or $json -eq "") { throw "Page produced no payload; check the console for a JS error." }

$items = $json | ConvertFrom-Json
Write-Output "Writing $($items.Count) files into $root"

foreach ($item in $items) {
    $bytes  = [System.Convert]::FromBase64String($item.b64)
    $target = Join-Path $root $item.name

    # Fail loudly on malformed XML rather than writing a file the browser cannot render.
    # An unescaped quote inside an attribute is the classic way this breaks.
    try {
        $xml = New-Object System.Xml.XmlDocument
        $xml.LoadXml([System.Text.Encoding]::UTF8.GetString($bytes))
    }
    catch {
        throw "$($item.name) is not valid XML: $($_.Exception.Message)"
    }

    [System.IO.File]::WriteAllBytes($target, $bytes)
    Write-Output ("  {0,-32} {1,6} bytes  valid" -f $item.name, $bytes.Length)
}

Write-Output "Done."
