# fetch-news.ps1 — Naver Search routine for the wiki vault.
# Fetches news+blog for tracked brands and market keywords, filters to the
# previous business day(s), and writes results into raw/.
# On Monday it looks back 3 days (Fri/Sat/Sun) so weekend data is not lost.
# No Korean literals here on purpose (config + output handled as UTF-8).

$ErrorActionPreference = "Stop"
$vault   = Split-Path $PSScriptRoot -Parent
$cfgPath = Join-Path $PSScriptRoot "config.json"
$cfg     = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Write-Utf8($path, $text) {
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# --- credentials -----------------------------------------------------------
$keyText = Get-Content (Join-Path $vault $cfg.keyFile) -Raw -Encoding UTF8
$cid = [regex]::Match($keyText, 'Client\s*ID\s+(\S+)').Groups[1].Value
$csec = [regex]::Match($keyText, 'Client\s*Secret\s+(\S+)').Groups[1].Value
if (-not $cid -or -not $csec) { throw "API key not found in $($cfg.keyFile)" }
$headers = @{ "X-Naver-Client-Id" = $cid; "X-Naver-Client-Secret" = $csec }

# --- target date window ----------------------------------------------------
$today = (Get-Date).Date
$lookback = if ($today.DayOfWeek -eq [DayOfWeek]::Monday) { 3 } else { 1 }
$targets = @{}
for ($i = 1; $i -le $lookback; $i++) { $targets[$today.AddDays(-$i).ToString('yyyyMMdd')] = $true }
$runStamp = $today.ToString('yyyy-MM-dd')
$rangeDesc = ($targets.Keys | Sort-Object) -join ', '
Write-Host "[fetch] run=$runStamp dow=$($today.DayOfWeek) targets=$rangeDesc"

function Strip([string]$s) { ($s -replace '<[^>]+>', '') -replace '&quot;', '"' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&#39;', "'" }

function Get-Items($type, $query, $targets) {
  $q = [uri]::EscapeDataString($query)
  $uri = "https://openapi.naver.com/v1/search/$type.json?query=$q&display=100&sort=date"
  $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
  $out = @()
  foreach ($it in $resp.items) {
    if ($type -eq 'news') {
      try { $d = ([datetime]::Parse($it.pubDate, [Globalization.CultureInfo]::InvariantCulture)).ToString('yyyyMMdd') } catch { continue }
    } else {
      $d = $it.postdate
    }
    if ($targets.ContainsKey($d)) {
      $out += [PSCustomObject]@{
        date = $d; title = Strip $it.title; link = $it.link
        desc = Strip $it.description; blogger = $it.bloggername
      }
    }
  }
  return $out
}

# --- brand monitoring ------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# 뉴스루틴 브랜드검색  (run=$runStamp / 대상일=$rangeDesc)")
[void]$sb.AppendLine()
foreach ($b in $cfg.brands) {
  Start-Sleep -Milliseconds 200
  $news = @(Get-Items 'news' $b.query $targets)
  Start-Sleep -Milliseconds 200
  $blog = @(Get-Items 'blog' $b.query $targets)
  [void]$sb.AppendLine("========== $($b.name)  [$($b.tag)] (query='$($b.query)') ==========")
  [void]$sb.AppendLine("  뉴스 $($news.Count)건 / 블로그 $($blog.Count)건")
  foreach ($n in ($news | Sort-Object date -Descending)) {
    [void]$sb.AppendLine("[뉴스] $($n.date) | $($n.title)")
    [void]$sb.AppendLine("        $($n.link)")
    if ($n.desc) { [void]$sb.AppendLine("        desc: $($n.desc)") }
  }
  foreach ($p in ($blog | Sort-Object date -Descending)) {
    [void]$sb.AppendLine("[블로그] $($p.date) | $($p.title) ($($p.blogger))")
    [void]$sb.AppendLine("        $($p.link)")
  }
  [void]$sb.AppendLine()
  Write-Host "  $($b.name): news=$($news.Count) blog=$($blog.Count)"
}
$brandPath = Join-Path $vault ($cfg.brandOut -replace '\{date\}', $runStamp)
Write-Utf8 $brandPath $sb.ToString()
Write-Host "[fetch] wrote $brandPath"

# --- market keywords -------------------------------------------------------
$mb = New-Object System.Text.StringBuilder
[void]$mb.AppendLine("# 뉴스루틴 시장키워드  (run=$runStamp / 대상일=$rangeDesc)")
[void]$mb.AppendLine()
foreach ($kw in $cfg.keywords) {
  Start-Sleep -Milliseconds 200
  $news = @(Get-Items 'news' $kw $targets)
  [void]$mb.AppendLine("===== '$kw' =====")
  foreach ($n in ($news | Sort-Object date -Descending)) {
    [void]$mb.AppendLine("$($n.date) | $($n.title)")
    [void]$mb.AppendLine("  LINK: $($n.link)")
    if ($n.desc) { [void]$mb.AppendLine("  desc: $($n.desc)") }
  }
  [void]$mb.AppendLine()
  Write-Host "  [$kw]: news=$($news.Count)"
}
$marketPath = Join-Path $vault ($cfg.marketOut -replace '\{date\}', $runStamp)
Write-Utf8 $marketPath $mb.ToString()
Write-Host "[fetch] wrote $marketPath"
Write-Host "[fetch] done."
