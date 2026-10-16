# Thông Dịch — downloads the AI models on your Windows PC (one time).
# Creates a folder "ThongDichModels" next to this script. Copy that folder to the iPhone app.
# Safe to run again: finished files are skipped and interrupted downloads resume.

param(
    [switch]$IncludeE4B,           # extra-quality translator for 12 GB iPhones (iPhone Air), +5.2 GB
    [switch]$SkipTranslateGemma    # leave out the optional TranslateGemma model (-2.2 GB)
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = Join-Path $PSScriptRoot 'ThongDichModels'
$curl = Join-Path $env:SystemRoot 'System32\curl.exe'
if (-not (Test-Path $curl)) { $curl = 'curl.exe' }

# Each model is pinned to an exact, tested version.
$models = @(
    @{ Name = 'Speech recognition (Parakeet Ultra)'; Repo = 'FluidInference/parakeet-ultra-coreml'; Rev = '95eaa59a39d4394f047a4dc5cce480388a60d1b6'
       Dest = 'speech\parakeet-ultra-coreml'
       Include = @('Preprocessor.mlmodelc/', 'Encoder.mlmodelc/', 'Decoder.mlmodelc/', 'JointDecisionv3.mlmodelc/', 'parakeet_vocab.json') },
    @{ Name = 'Voice detector (Silero VAD)'; Repo = 'FluidInference/silero-vad-coreml'; Rev = 'b419383c55c110e2c9271fa6ee0ea83d03c70d96'
       Dest = 'speech\silero-vad'
       Include = @('silero-vad-unified-256ms-v6.2.1.mlmodelc/') },
    @{ Name = 'Translator: Gemma 4 E2B'; Repo = 'mlx-community/gemma-4-e2b-it-4bit'; Rev = '238767527555cb75a05732a84dff5d6ba0dd6809'
       Dest = 'translator\gemma-4-e2b-it-4bit'
       Include = @('*.json', '*.jinja', '*.safetensors') }
)
if (-not $SkipTranslateGemma) {
    $models += @{ Name = 'Translator: TranslateGemma 4B'; Repo = 'mlx-community/translategemma-4b-it-4bit'; Rev = '5788ec08c047f3f2e17808101b8d9566ac930d58'
                  Dest = 'translator\translategemma-4b-it-4bit'
                  Include = @('*.json', '*.jinja', '*.safetensors') }
}
if ($IncludeE4B) {
    $models += @{ Name = 'Translator: Gemma 4 E4B (iPhone Air)'; Repo = 'mlx-community/gemma-4-e4b-it-4bit'; Rev = '475b9088d29754a3379866cf5aeb6b41acd313c2'
                  Dest = 'translator\gemma-4-e4b-it-4bit'
                  Include = @('*.json', '*.jinja', '*.safetensors') }
}

function Test-Wanted([string]$path, [string[]]$include) {
    foreach ($pattern in $include) {
        if ($pattern.EndsWith('/')) {
            if ($path.StartsWith($pattern)) { return $true }
        } elseif ($pattern.Contains('*')) {
            if (-not $path.Contains('/') -and ($path -like $pattern)) { return $true }
        } elseif ($path -eq $pattern) { return $true }
    }
    return $false
}

function Format-Size([double]$bytes) {
    if ($bytes -ge 1GB) { return '{0:N2} GB' -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return '{0:N1} MB' -f ($bytes / 1MB) }
    return '{0:N0} KB' -f ($bytes / 1KB)
}

Write-Host ''
Write-Host '  Thong Dich - model downloader' -ForegroundColor Cyan
Write-Host "  Saving to: $root"
Write-Host ''

# 1) List the files of every model
$plan = @()
foreach ($m in $models) {
    Write-Host "  Checking $($m.Name)..."
    $url = "https://huggingface.co/api/models/$($m.Repo)/tree/$($m.Rev)?recursive=true"
    $tree = Invoke-RestMethod -Uri $url -UseBasicParsing
    foreach ($entry in $tree) {
        if ($entry.type -ne 'file') { continue }
        if (-not (Test-Wanted $entry.path $m.Include)) { continue }
        $plan += [pscustomobject]@{
            Model = $m.Name
            Url   = "https://huggingface.co/$($m.Repo)/resolve/$($m.Rev)/$($entry.path)"
            Out   = Join-Path (Join-Path $root $m.Dest) ($entry.path -replace '/', '\')
            Size  = [int64]$entry.size
        }
    }
}

$total = ($plan | Measure-Object -Property Size -Sum).Sum
$have = 0
foreach ($f in $plan) { if ((Test-Path $f.Out) -and ((Get-Item $f.Out).Length -eq $f.Size)) { $have += $f.Size } }
$drive = (Get-Item $PSScriptRoot).PSDrive
$free = $drive.Free
Write-Host ''
Write-Host ("  Total: {0}   Already downloaded: {1}   Free on {2}: {3}" -f (Format-Size $total), (Format-Size $have), $drive.Name, (Format-Size $free))
if (($total - $have) -gt $free) {
    Write-Host '  Not enough free disk space. Free up space and run again.' -ForegroundColor Red
    exit 1
}
Write-Host ''

# 2) Download (resumable)
$done = 0
$i = 0
foreach ($f in $plan) {
    $i++
    $dir = Split-Path $f.Out -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    if ((Test-Path $f.Out) -and ((Get-Item $f.Out).Length -eq $f.Size)) {
        $done += $f.Size
        continue
    }
    $leaf = Split-Path $f.Out -Leaf
    Write-Host ("  [{0}/{1}] {2} - {3} ({4})" -f $i, $plan.Count, $f.Model, $leaf, (Format-Size $f.Size))
    $ok = $false
    for ($attempt = 1; $attempt -le 6 -and -not $ok; $attempt++) {
        & $curl -L --fail --retry 5 --retry-delay 3 -C - --progress-bar -o $f.Out $f.Url
        if ((Test-Path $f.Out) -and ((Get-Item $f.Out).Length -eq $f.Size)) { $ok = $true }
        elseif ((Test-Path $f.Out) -and ((Get-Item $f.Out).Length -gt $f.Size)) { Remove-Item $f.Out -Force }
        if (-not $ok) { Write-Host "    retrying ($attempt)..." -ForegroundColor Yellow; Start-Sleep -Seconds 3 }
    }
    if (-not $ok) {
        Write-Host "  Download failed: $leaf. Check your internet connection and run Get-Models.bat again (it will resume)." -ForegroundColor Red
        exit 1
    }
    $done += $f.Size
    Write-Host ("    overall {0:N0}%" -f (100 * $done / [math]::Max(1, $total))) -ForegroundColor DarkGray
}

# 3) Pack each model into ONE file (.tdpack) so it can be dragged into the iPhone app
#    with Apple Devices / iTunes file sharing (which copies files, not folders).
#    Format: "TDPACK1", then one "relative/path<TAB>size" line per file, an empty line, then the bytes.
$transfer = Join-Path $PSScriptRoot 'ThongDich-Transfer'
New-Item -ItemType Directory -Force -Path $transfer | Out-Null

function New-TdPack([string]$packName, [string[]]$folders) {
    $packPath = Join-Path $transfer $packName
    $files = @()
    foreach ($folder in $folders) {
        $full = Join-Path $root $folder
        if (Test-Path $full) { $files += Get-ChildItem -Path $full -Recurse -File | Sort-Object FullName }
    }
    if ($files.Count -eq 0) { return }
    $size = ($files | Measure-Object -Property Length -Sum).Sum
    if ((Test-Path $packPath) -and ((Get-Item $packPath).LastWriteTime -gt ($files | Sort-Object LastWriteTime | Select-Object -Last 1).LastWriteTime)) {
        Write-Host "  $packName is up to date."
        return
    }
    Write-Host ("  Packing {0} ({1})..." -f $packName, (Format-Size $size))
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("TDPACK1`n")
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
        [void]$sb.Append("$rel`t$($f.Length)`n")
    }
    [void]$sb.Append("`n")
    $headerBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($sb.ToString())
    $tmp = "$packPath.partial"
    $out = [System.IO.File]::Create($tmp)
    try {
        $out.Write($headerBytes, 0, $headerBytes.Length)
        foreach ($f in $files) {
            $in = [System.IO.File]::OpenRead($f.FullName)
            try { $in.CopyTo($out, 8388608) } finally { $in.Dispose() }
        }
    } finally { $out.Dispose() }
    if (Test-Path $packPath) { Remove-Item $packPath -Force }
    Rename-Item -Path $tmp -NewName $packName
}

$freeNow = (Get-Item $PSScriptRoot).PSDrive.Free
if ($freeNow -lt $total) {
    Write-Host '  Not enough disk space to also make the transfer packs.' -ForegroundColor Yellow
    Write-Host '  You can still copy the ThongDichModels folder with a USB-C drive (see the guide).' -ForegroundColor Yellow
} else {
    Write-Host ''
    New-TdPack 'thongdich-speech.tdpack' @('speech')
    New-TdPack 'thongdich-gemma-4-e2b.tdpack' @('translator\gemma-4-e2b-it-4bit')
    New-TdPack 'thongdich-translategemma-4b.tdpack' @('translator\translategemma-4b-it-4bit')
    New-TdPack 'thongdich-gemma-4-e4b.tdpack' @('translator\gemma-4-e4b-it-4bit')
}

Write-Host ''
Write-Host '  All done!' -ForegroundColor Green
Write-Host ''
Write-Host '  Next:'
Write-Host '   1. Connect your iPhone with a cable and open the Apple Devices app (or iTunes).'
Write-Host '   2. Select your iPhone > Files > Thong Dich.'
Write-Host "   3. Drag ALL the .tdpack files from this folder into it:"
Write-Host "      $transfer"
Write-Host '   4. Open Thong Dich on the iPhone - it installs them by itself (no internet needed).'
Write-Host ''
Start-Process explorer.exe $transfer
