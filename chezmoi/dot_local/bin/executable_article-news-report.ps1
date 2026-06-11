#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [ValidateRange(1, 20)]
    [int]$Count = 5,

    [string]$OutDir = (Join-Path $env:TEMP ("article-news-report-" + (Get-Date -Format "yyyyMMdd-HHmmss"))),

    [ValidateSet("hackernews")]
    [string]$Source = "hackernews"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ArticleCollector {
    $candidates = @(
    (Join-Path $env:USERPROFILE ".local\bin\article-collector.exe"),
    (Join-Path $env:USERPROFILE ".local\bin\article-collector")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    $command = Get-Command article-collector -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $command = Get-Command article-collector.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "article-collector is not installed. Expected it in ~/.local/bin."
}

function ConvertTo-SlackLink {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $safeText = $Text.Replace("|", "-").Replace("<", "(").Replace(">", ")")
    return "<$Url|$safeText>"
}

function Invoke-ArticleCollectorFetch {
    param(
        [Parameter(Mandatory = $true)][string]$ArticleCollector,
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$ItemDir
    )

    New-Item -ItemType Directory -Path $ItemDir -Force | Out-Null

    $oldOutDir = [Environment]::GetEnvironmentVariable("ARTICLE_COLLECTOR_OUTDIR", "Process")
    try {
        $env:ARTICLE_COLLECTOR_OUTDIR = $ItemDir
        $output = & $ArticleCollector fetch $Url 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            $joined = ($output | Out-String).Trim()
            throw "article-collector fetch failed (exit=$exitCode): $joined"
        }

        $rawPath = Join-Path $ItemDir "raw.json"
        if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
            throw "article-collector did not create raw.json for $Url"
        }

        $raw = Get-Content -LiteralPath $rawPath -Raw | ConvertFrom-Json
        if ($raw -is [array]) {
            return $raw[0]
        }

        return $raw
    }
    finally {
        if ($null -eq $oldOutDir) {
            Remove-Item Env:\ARTICLE_COLLECTOR_OUTDIR -ErrorAction SilentlyContinue
        }
        else {
            $env:ARTICLE_COLLECTOR_OUTDIR = $oldOutDir
        }
    }
}

function Get-HackerNewsReportItem {
    param(
        [Parameter(Mandatory = $true)][string]$ArticleCollector,
        [Parameter(Mandatory = $true)][string]$ReportOutDir,
        [Parameter(Mandatory = $true)][int]$Limit
    )

    $topIdsJson = (Invoke-WebRequest -UseBasicParsing -Uri "https://hacker-news.firebaseio.com/v0/topstories.json" -TimeoutSec 20).Content
    $topIds = [System.Text.Json.JsonSerializer]::Deserialize[long[]]($topIdsJson)
    if ($topIds.Count -eq 0) {
        throw "Hacker News topstories returned no IDs."
    }

    $items = New-Object System.Collections.Generic.List[object]
    $failures = New-Object System.Collections.Generic.List[string]
    $scanLimit = [Math]::Min($topIds.Count, [Math]::Max($Limit * 4, $Limit))

    for ($index = 0; $index -lt $scanLimit -and $items.Count -lt $Limit; $index++) {
        $id = [string]$topIds[$index]
        $itemUrl = "https://news.ycombinator.com/item?id=$id"
        $itemDir = Join-Path $ReportOutDir ("hn-" + $id)

        try {
            $item = Invoke-ArticleCollectorFetch -ArticleCollector $ArticleCollector -Url $itemUrl -ItemDir $itemDir
            if (-not $item) {
                continue
            }

            $title = if ($item.title) { [string]$item.title } else { "Untitled" }
            $link = if ($item.url) { [string]$item.url } else { $itemUrl }
            $author = if ($item.author) { [string]$item.author } else { "unknown" }
            $score = if ($null -ne $item.score) { [int]$item.score } else { 0 }
            $comments = if ($null -ne $item.descendants) { [int]$item.descendants } else { 0 }

            $items.Add([pscustomobject]@{
                    Id       = $id
                    Title    = $title
                    Url      = $link
                    HnUrl    = $itemUrl
                    Author   = $author
                    Score    = $score
                    Comments = $comments
                }) | Out-Null
        }
        catch {
            $failures.Add("${itemUrl}: $($_.Exception.Message)") | Out-Null
        }
    }

    return [pscustomobject]@{
        Items    = $items.ToArray()
        Failures = $failures.ToArray()
    }
}

$articleCollector = Resolve-ArticleCollector
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

if ($Source -eq "hackernews") {
    $result = Get-HackerNewsReportItem -ArticleCollector $articleCollector -ReportOutDir $OutDir -Limit $Count
}
else {
    throw "Unsupported source: $Source"
}

$items = @($result.Items)
$failures = @($result.Failures)

if ($items.Count -eq 0) {
    $failureText = if ($failures.Count -gt 0) { $failures -join "`n" } else { "No items collected." }
    throw "article-news-report produced no report items. $failureText"
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("*Hourly article-collector report*") | Out-Null
$lines.Add("Generated: $timestamp") | Out-Null
$lines.Add("Source: Hacker News top stories") | Out-Null
$lines.Add(("OutDir: ``{0}``" -f $OutDir)) | Out-Null
$lines.Add("") | Out-Null

for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items[$i]
    $rank = $i + 1
    $articleUrl = [string]($item.Url)
    $articleTitle = [string]($item.Title)
    $hnUrl = [string]($item.HnUrl)
    $articleLink = ConvertTo-SlackLink -Url $articleUrl -Text $articleTitle
    $hnLink = ConvertTo-SlackLink -Url $hnUrl -Text "HN"
    $lines.Add(("{0}. {1}" -f $rank, $articleLink)) | Out-Null
    $lines.Add(("   {0} points, {1} comments, by {2} ({3})" -f $item.Score, $item.Comments, $item.Author, $hnLink)) | Out-Null
}

if ($failures.Count -gt 0) {
    $lines.Add("") | Out-Null
    $lines.Add("*Warnings*") | Out-Null
    foreach ($failure in $failures | Select-Object -First 5) {
        $lines.Add("- $failure") | Out-Null
    }
}

$lines -join "`n"
