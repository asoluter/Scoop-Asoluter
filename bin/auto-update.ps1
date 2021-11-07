<#
.SYNOPSIS
    Updates manifests and pushes them.
.DESCRIPTION
    Updates manifests and pushes them directly to the main branch.
.PARAMETER Upstream
    Upstream repository with the target branch.
    Must be in format '<user>/<repo>:<branch>'
.PARAMETER App
    Manifest name to search.
    Placeholders are supported.
.PARAMETER Dir
    The directory where to search for manifests.
.PARAMETER Push
    Push updates directly to 'origin main'.
.PARAMETER Help
    Print help to console.
.PARAMETER SpecialSnowflakes
    An array of manifests, which should be updated all the time. (-ForceUpdate parameter to checkver)
.PARAMETER SkipUpdated
    Updated manifests will not be shown.
.EXAMPLE
    PS BUCKETROOT > .\bin\auto-pr.ps1 'someUsername/repository:branch' -Request
.EXAMPLE
    PS BUCKETROOT > .\bin\auto-pr.ps1 -Push
    Update all manifests inside 'bucket/' directory.
#>

param(
    [ValidateScript( {
        if (!($_ -match '^(.*)\/(.*):(.*)$')) {
            throw 'Upstream must be in this format: <user>/<repo>:<branch>'
        }
        $true
    })]
    [String] $Upstream = "asoluter/Scoop-Asoluter:main",
    [String] $App = '*',
    [ValidateScript( {
        if (!(Test-Path $_ -Type Container)) {
            throw "$_ is not a directory!"
        } else {
            $true
        }
    })]
    [String] $Dir = "$psscriptroot/../bucket",
    [string[]] $SpecialSnowflakes,
    [Switch] $SkipUpdated
)

. "$env:SCOOP_HOME\lib\manifest.ps1"
. "$env:SCOOP_HOME\lib\json.ps1"
. "$env:SCOOP_HOME\lib\unix.ps1"

$Dir = Resolve-Path $Dir

function execute($cmd) {
    Write-Host $cmd -ForegroundColor Green
    $output = Invoke-Expression $cmd

    if ($LASTEXITCODE -gt 0) {
        abort "^^^ Error! See above ^^^ (last command: $cmd)"
    }

    return $output
}

Write-Host 'Updating ...' -ForegroundColor DarkCyan
execute 'git pull origin main'
execute 'git checkout main'

. "$env:SCOOP_HOME\bin\checkver.ps1" -App $App -Dir $Dir -Update -SkipUpdated:$SkipUpdated
if ($SpecialSnowflakes) {
    Write-Host "Forcing update on our special snowflakes: $($SpecialSnowflakes -join ',')" -ForegroundColor DarkCyan
    $SpecialSnowflakes -split ',' | ForEach-Object {
        . "$env:SCOOP_HOME\bin\checkver.ps1" $_ -Dir $Dir -ForceUpdate
    }
}

git diff --name-only | ForEach-Object {
    $manifest = $_
    if (!$manifest.EndsWith('.json')) {
        return
    }

    $app = ([System.IO.Path]::GetFileNameWithoutExtension($manifest))
    $json = parse_json $manifest
    if (!$json.version) {
        error "Invalid manifest: $manifest ..."
        return
    }
    $version = $json.version

    Write-Host "Creating update $app ($version) ..." -ForegroundColor DarkCyan
    execute "git add $manifest"

    # detect if file was staged, because it's not when only LF or CRLF have changed
    $status = execute 'git status --porcelain -uno'
    $status = $status | Where-Object { $_ -match "M\s{2}.*$app.json" }
    if ($status -and $status.StartsWith('M  ') -and $status.EndsWith("$app.json")) {
        execute "git commit -m '${app}: Update to version $version'"
    } else {
        Write-Host "Skipping $app because only LF/CRLF changes were detected ..." -ForegroundColor Yellow
    }
}

Write-Host 'Pushing updates ...' -ForegroundColor DarkCyan
execute 'git push origin main'

execute 'git reset --hard'
