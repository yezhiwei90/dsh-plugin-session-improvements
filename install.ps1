#Requires -Version 5.1
<#
.SYNOPSIS
  Install or rollback the dsh-plugin-session-improvements patch for deepseek-harness.

.PARAMETER HarnessRoot
  Path to the deepseek-harness git checkout. Defaults to $env:DSH_HARNESS_ROOT,
  then the current directory (walking up until a .git with packages/host/apiproxy is found).

.PARAMETER CheckOnly
  Verify the patch applies cleanly; change nothing.

.PARAMETER Build
  Run `pnpm run build` after applying.

.PARAMETER Test
  Run the affected test suites after applying.

.PARAMETER Rollback
  Reverse-apply the patch (and restore the latest backup if present).
#>
[CmdletBinding()]
param(
  [string]$HarnessRoot,
  [switch]$CheckOnly,
  [switch]$Build,
  [switch]$Test,
  [switch]$Rollback
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Patch = Join-Path $ScriptDir 'dsh-plugin-session-improvements.patch'
$FileList = Join-Path $ScriptDir 'file-list.txt'

function Fail([string]$msg) { Write-Host "[dsh-plugin-session-improvements] $msg" -ForegroundColor Red; exit 1 }

# --- locate the harness root -------------------------------------------------
if (-not $HarnessRoot) { $HarnessRoot = $env:DSH_HARNESS_ROOT }
if (-not $HarnessRoot) {
  $dir = Get-Location
  while ($dir -and $dir.Path) {
    if (Test-Path (Join-Path $dir '.git') -and (Test-Path (Join-Path $dir 'packages\host\apiproxy'))) { $HarnessRoot = $dir.Path; break }
    $dir = $dir.Parent
  }
}
if (-not $HarnessRoot -or -not (Test-Path $HarnessRoot)) { Fail "deepseek-harness checkout not found; pass -HarnessRoot" }
Push-Location $HarnessRoot
try {
  & git rev-parse --is-inside-work-tree *> $null
  if ($LASTEXITCODE -ne 0) { Fail "$HarnessRoot is not a git worktree" }
  $head = & git rev-parse --short HEAD
  Write-Host "[dsh-plugin-session-improvements] harness root : $HarnessRoot"
  Write-Host "[dsh-plugin-session-improvements] HEAD commit  : $head (patch baseline: 47f943859b)"

  # --- rollback --------------------------------------------------------------
  if ($Rollback) {
    if (& git apply -R --check $Patch) {
      Write-Host "[dsh-plugin-session-improvements] patch reverse-applies cleanly; rolling back..."
      & git apply -R $Patch
      if ($LASTEXITCODE -ne 0) { Fail "reverse apply failed" }
      Write-Host "[dsh-plugin-session-improvements] rolled back. (Backup copies remain under dsh-plugin-session-improvements-backup-* if you made one.)"
      exit 0
    }
    Fail "patch does not reverse-apply cleanly here; check which files changed since install (git status) and restore from files/original/ manually."
  }

  # --- preflight -------------------------------------------------------------
  & git apply --check $Patch
  if ($LASTEXITCODE -ne 0) {
    Fail "patch does NOT apply cleanly (upstream drift?). Review files/original vs files/modified and merge manually."
  }
  if ($CheckOnly) {
    Write-Host "[dsh-plugin-session-improvements] OK: patch applies cleanly; no changes made."
    exit 0
  }
  # warn (not fail) on a dirty tree touching our files
  $dirty = & git status --porcelain | Where-Object { $_ -ne '' }
  if ($dirty) {
    Write-Warning "working tree has uncommitted changes; the patch will be applied on top of them."
  }

  # --- backup the 45 target files --------------------------------------------
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $backup = Join-Path $HarnessRoot "dsh-plugin-session-improvements-backup-$stamp"
  $files = Get-Content $FileList | Where-Object { $_ -ne '' }
  foreach ($f in $files) {
    $src = Join-Path $HarnessRoot $f
    if (-not (Test-Path $src)) { continue }
    $dst = Join-Path $backup $f
    New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
    Copy-Item $src $dst -Force
  }
  Write-Host "[dsh-plugin-session-improvements] backup written : $backup"

  # --- apply -------------------------------------------------------------------
  & git apply --stat $Patch | Out-Null
  & git apply $Patch
  if ($LASTEXITCODE -ne 0) { Fail "git apply failed" }
  Write-Host "[dsh-plugin-session-improvements] patch applied: $($files.Count) files."

  if ($Build) {
    Write-Host "[dsh-plugin-session-improvements] running pnpm run build ..."
    & pnpm run build
    if ($LASTEXITCODE -ne 0) { Fail "build failed (patch still applied; use -Rollback to revert)" }
  }
  if ($Test) {
    Write-Host "[dsh-plugin-session-improvements] running affected tests ..."
    & pnpm vitest run packages/session/session-persistence/tests/persistence.spec.ts
    if ($LASTEXITCODE -ne 0) { Fail "persistence tests failed" }
    & pnpm vitest run packages/client packages/host packages/test-support
    if ($LASTEXITCODE -ne 0) { Fail "client/host/test-support tests failed" }
    & pnpm vitest run --config vitest.web.config.ts apps/web/tests/workspace-management.e2e.ts
    if ($LASTEXITCODE -ne 0) { Fail "web e2e failed" }
  }
  Write-Host ""
  Write-Host "[dsh-plugin-session-improvements] DONE. Restart your dsh process to activate (e.g. dsh web)." -ForegroundColor Green
}
finally {
  Pop-Location
}
