# Tests for install.ps1's install decisions. Everything that would touch the machine is replaced:
# Git, the GitHub CLI and bash are a stand-in program, and winget, the downloads, the signature check and
# the installers are functions defined here. Nothing is installed, downloaded or signed in.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\install.tests.ps1
param([string]$Script = (Join-Path $PSScriptRoot '..\install.ps1'))
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP ('dp-bootstrap-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $root | Out-Null
# The stand-in for git.exe, gh.exe and bash.exe: a copy of a signed Windows program that exits 0 whatever
# it is given. (A stub compiled here would be unsigned, and Windows application control blocks those.)
$stub = Join-Path $env:SystemRoot 'System32\doskey.exe'
$realProgramFiles = $env:ProgramFiles; $realPath = $env:Path

function Put-Tool($id) {
  if ($id -eq 'Git.Git') {
    foreach ($d in 'cmd', 'bin') { New-Item -ItemType Directory -Force (Join-Path $env:ProgramFiles "Git\$d") | Out-Null }
    Copy-Item $stub (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'); Copy-Item $stub (Join-Path $env:ProgramFiles 'Git\bin\bash.exe')
  } else {
    New-Item -ItemType Directory -Force (Join-Path $env:ProgramFiles 'GitHub CLI') | Out-Null
    Copy-Item $stub (Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe')
  }
}

# The replacements. install.ps1 runs in a child scope, so it resolves these before the real commands.
function Get-Command {
  if ($args -contains 'winget') { if ($global:DPT.winget) { return 'winget' } else { return $null } }
  Microsoft.PowerShell.Core\Get-Command @args
}
function Install-PackageProvider { $global:DPT.calls += 'bootstrap-winget'; if ($global:DPT.bootstrap -ne 'ok') { throw 'no package gallery here' } }
function Install-Module { }
function Repair-WinGetPackageManager { $global:DPT.winget = $true }
function winget.exe {
  $id = $args[($args.IndexOf('--id') + 1)]; $global:DPT.calls += "winget $id"
  if ($global:DPT.wingetInstall -eq 'ok') { Put-Tool $id } else { 'No package found matching input criteria.' }
}
function Invoke-RestMethod {
  [pscustomobject]@{ assets = @(
      [pscustomobject]@{ name = 'Git-9.9.9-64-bit.exe'; browser_download_url = 'https://example.invalid/git.exe' },
      [pscustomobject]@{ name = 'gh_9.9.9_windows_amd64.msi'; browser_download_url = 'https://example.invalid/gh.msi' }) }
}
function Invoke-WebRequest { param($Uri, $OutFile) Set-Content -Path $OutFile -Value 'not a real installer' }
function Get-AuthenticodeSignature {
  param($f)
  $who = if ($f -like '*Git-*') { 'CN=Johannes Schindelin, O=Johannes Schindelin' } else { 'CN="GitHub, Inc.", O="GitHub, Inc."' }
  if ($global:DPT.signer) { $who = $global:DPT.signer }
  [pscustomobject]@{ Status = $global:DPT.signature; SignerCertificate = [pscustomobject]@{ Subject = $who } }
}
function Start-Process {
  param($FilePath, $ArgumentList, $Verb, [switch]$Wait)
  $id = if ($FilePath -like '*Git-*') { 'Git.Git' } else { 'GitHub.cli' }
  $global:DPT.calls += "official $id"; Put-Tool $id
}

$failed = 0
function Case($name, [string[]]$have, [hashtable]$set, [scriptblock]$expect) {
  $env:ProgramFiles = Join-Path $root ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force $env:ProgramFiles | Out-Null
  $global:DPT = @{ calls = @(); winget = $false; bootstrap = 'fail'; wingetInstall = 'ok'; signature = 'Valid'; signer = $null }
  foreach ($k in $set.Keys) { $global:DPT[$k] = $set[$k] }
  foreach ($id in $have) { Put-Tool $id }
  $threw = $null
  try { $out = (& $Script *>&1 | Out-String) } catch { $threw = $_.Exception.Message; $out = '' }
  $env:Path = $realPath
  $problem = & $expect $global:DPT.calls $out $threw
  if ($problem) { $script:failed++; Write-Host "FAIL  $name`n      $problem`n      calls: $($global:DPT.calls -join ', ')  threw: $threw" }
  else { Write-Host "ok    $name" }
}
$both = 'Git.Git', 'GitHub.cli'

Case 'both tools present, no winget: installs nothing' $both @{} {
  param($calls, $out, $threw)
  if ($threw) { return "threw: $threw" }
  if ($calls.Count) { return 'it tried to install something' }
  if ($out -match 'Installing') { return 'it said it was installing' }
  if ($out -notmatch 'ok   workspace') { return 'it did not reach the workspace step' }
}
Case 'both tools present, winget present: installs nothing' $both @{ winget = $true } {
  param($calls, $out, $threw)
  if ($threw -or $calls.Count) { return "expected no installs (threw: $threw)" }
}
Case 'Git missing, no winget and none obtainable: official installer' @('GitHub.cli') @{} {
  param($calls, $out, $threw)
  if ($threw) { return "threw: $threw" }
  if (($calls -join ',') -ne 'bootstrap-winget,official Git.Git') { return 'expected one winget attempt, then the official Git installer' }
  if ($out -notmatch 'Carrying on with the official installers') { return 'it did not say why it switched' }
}
Case 'GitHub CLI missing, winget obtainable: winget installs it' @('Git.Git') @{ bootstrap = 'ok' } {
  param($calls, $out, $threw)
  if ($threw) { return "threw: $threw" }
  if (($calls -join ',') -ne 'bootstrap-winget,winget GitHub.cli') { return 'expected winget to be set up and used' }
}
Case 'GitHub CLI missing, winget present but fails: official installer' @('Git.Git') @{ winget = $true; wingetInstall = 'fail' } {
  param($calls, $out, $threw)
  if ($threw) { return "threw: $threw" }
  if (($calls -join ',') -ne 'winget GitHub.cli,official GitHub.cli') { return 'expected winget, then the official installer' }
  if ($out -notmatch "winget couldn't install GitHub.cli") { return 'it did not show the winget error' }
}
Case 'neither tool, no winget: both from the official installers' @() @{} {
  param($calls, $out, $threw)
  if ($threw) { return "threw: $threw" }
  if (($calls -join ',') -ne 'bootstrap-winget,official Git.Git,official GitHub.cli') { return 'expected one winget attempt, then both official installers' }
}
Case 'unsigned download is never run' @('GitHub.cli') @{ signature = 'NotSigned' } {
  param($calls, $out, $threw)
  if ($threw -notmatch "isn't validly signed") { return 'expected it to refuse the download' }
  if ($calls -contains 'official Git.Git') { return 'it ran an unsigned installer' }
}
Case 'download signed by someone else is never run' @('GitHub.cli') @{ signer = 'CN=Somebody Else' } {
  param($calls, $out, $threw)
  if ($threw -notmatch 'not Johannes Schindelin') { return 'expected it to refuse the download' }
  if ($calls -contains 'official Git.Git') { return 'it ran an installer from the wrong publisher' }
}

$env:ProgramFiles = $realProgramFiles; $env:Path = $realPath
Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
if ($failed) { Write-Host "`n$failed failed"; exit 1 } else { Write-Host "`nall passed" }
