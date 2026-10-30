param(
  [string]$MediaRoot = "C:\UIPath\mandai-product-management\backend\media\products",
  [string]$MappingCsv = "$PSScriptRoot\product_folder_map.csv",
  [string]$OutputSql = "$PSScriptRoot\02_verified_media_updates.sql"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $MediaRoot -PathType Container)) { throw "Media folder missing: $MediaRoot" }
$angles = @(0,45,90,135,180,225,270,315)
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('-- GENERATED FROM ACTUAL DISK FILES; review BEFORE executing.')
[void]$sb.AppendLine('USE [MandaiDB];')
[void]$sb.AppendLine('GO')
[void]$sb.AppendLine('SET XACT_ABORT ON;')
[void]$sb.AppendLine('BEGIN TRANSACTION;')
$complete = 0; $single = 0; $missing = 0
foreach($m in (Import-Csv -LiteralPath $MappingCsv)) {
  $name = $m.ProductName
  $folder = $m.FolderName
  $dir = Join-Path $MediaRoot $folder
  $frames = @($angles | ForEach-Object { 'angle_{0:D3}.jpg' -f $_ })
  $allFrames = (Test-Path -LiteralPath $dir -PathType Container)
  if ($allFrames) {
    foreach($f in $frames){
      $file = Join-Path $dir $f
      if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -le 1000) { $allFrames = $false; break }
    }
  }
  # A cap may have an older slug subfolder instead of the 8-frames folder.
  if (-not $allFrames -and $folder -eq 'tropical_trail_embroidered_cap_8_frames') {
    $alternate = 'tropical-trail-cap'
    $otherdir = Join-Path $MediaRoot $alternate
    if (Test-Path -LiteralPath $otherdir -PathType Container) {
      $allAlternate = $true
      foreach($f in $frames){
        $file=Join-Path $otherdir $f
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -le 1000) {$allAlternate=$false;break}
      }
      if ($allAlternate) { $folder=$alternate; $dir=$otherdir; $allFrames=$true }
    }
  }
  $safeName=$name.Replace("'","''")
  $safeFolder=[uri]::EscapeDataString($folder)
  if ($allFrames) {
    $urls=@($frames | ForEach-Object { "/media/products/$safeFolder/$_" })
    $spin=($urls -join "`n").Replace("'","''")
    $image=$urls[0]
    [void]$sb.AppendLine("-- 8 verified JPG frames: $name")
    [void]$sb.AppendLine("UPDATE dbo.Products SET ImageUrl = CASE WHEN NULLIF(LTRIM(RTRIM(ImageUrl)),N'') IS NULL THEN N'$image' ELSE ImageUrl END, SpinImageUrls = CASE WHEN NULLIF(LTRIM(RTRIM(SpinImageUrls)),N'') IS NULL THEN N'$spin' ELSE SpinImageUrls END WHERE Name=N'$safeName';")
    $complete++
    Write-Host "360 OK: $name ($folder)"
  } else {
    $dir=Join-Path $MediaRoot $folder
    $candidate=@('primary.jpg','angle_000.jpg')
    $existing=@($candidate | Where-Object { $f=Join-Path $dir $_; (Test-Path -LiteralPath $f -PathType Leaf) -and (Get-Item -LiteralPath $f).Length -gt 1000 })
    if($existing.Count -gt 0){
      $image="/media/products/$safeFolder/$($existing[0])"
      [void]$sb.AppendLine("-- Single validated preview only; no 360° sequence: $name")
      [void]$sb.AppendLine("UPDATE dbo.Products SET ImageUrl=N'$image' WHERE Name=N'$safeName' AND NULLIF(LTRIM(RTRIM(ImageUrl)),N'') IS NULL;")
      $single++
      Write-Host "SINGLE only: $name ($folder)"
    } else { $missing++; Write-Warning "NO VALID MEDIA: $name ($folder)" }
  }
}
[void]$sb.AppendLine('COMMIT TRANSACTION;')
[void]$sb.AppendLine('GO')
[void]$sb.AppendLine('SELECT Id,Name,ImageUrl,SpinImageUrls FROM dbo.Products WHERE SpinImageUrls IS NOT NULL;')
[System.IO.File]::WriteAllText($OutputSql,$sb.ToString(),[System.Text.UTF8Encoding]::new($true))
Write-Host "Generated: $OutputSql"
Write-Host "Verified 360: $complete; single preview: $single; no image: $missing"
Write-Warning 'SQL does not validate browser accessibility: ensure FastAPI serves /media/products/<folder>/<file>.'
