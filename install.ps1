# DetailPage workspace bootstrap for Windows. Public on purpose: it runs before you're signed in to
# GitHub, so it can't live in the private repo. It installs winget (if missing), Git and the GitHub
# CLI, signs you in to GitHub, clones detail-page/engineering-workspace, then hands off to its SETUP.md,
# which your Claude app runs for you.
#   irm https://raw.githubusercontent.com/detail-page/workspace-setup/main/install.ps1 | iex
& {
  # 'Continue': in Windows PowerShell 5.1, 'Stop' turns any stderr from gh/git/winget into a fatal error,
  # even when redirected. Every failure below is checked and explained explicitly instead.
  $ErrorActionPreference = 'Continue'
  $ProgressPreference = 'SilentlyContinue'  # PowerShell 5.1's progress bar makes downloads very slow
  Set-ExecutionPolicy -Scope Process Bypass -Force
  [Console]::OutputEncoding = [Text.Encoding]::UTF8
  $repo = Join-Path $HOME 'engineering-workspace'
  function Say($m) { Write-Host $m }
  function Fresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') + ";$env:LOCALAPPDATA\Microsoft\WindowsApps" }
  Say "`n==> DetailPage workspace: getting started"
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Say "  Installing winget (Windows' package manager)..."
    $ProgressPreference = 'SilentlyContinue'
    # Older Windows PowerShell setups default to TLS 1.0/1.1, which PowerShell Gallery refuses.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    try {
      Install-PackageProvider -Name NuGet -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
      Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Repository PSGallery -Force -ErrorAction Stop | Out-Null
      Repair-WinGetPackageManager -Force -Latest -ErrorAction Stop | Out-Null
    } catch { throw "Couldn't install winget ($($_.Exception.Message)). Install 'App Installer' from the Microsoft Store, then run this again." }
    Fresh-Path
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget still isn't available. Install 'App Installer' from the Microsoft Store, then run this again." }
  }
  $git = "$env:ProgramFiles\Git\cmd\git.exe"; $gh = "$env:ProgramFiles\GitHub CLI\gh.exe"; $bash = "$env:ProgramFiles\Git\bin\bash.exe"
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  # Official installers, used when winget can't (a broken winget source is common on fresh PCs).
  function Install-Official($name) {
    $T = Join-Path $env:TEMP 'dp-workspace'; New-Item -ItemType Directory -Force $T | Out-Null
    if ($name -eq 'Git.Git') {
      $a = (Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest').assets | Where-Object { $_.name -like 'Git-*-64-bit.exe' } | Select-Object -First 1
    } else {
      $a = (Invoke-RestMethod 'https://api.github.com/repos/cli/cli/releases/latest').assets | Where-Object { $_.name -like 'gh_*_windows_amd64.msi' } | Select-Object -First 1
    }
    $f = Join-Path $T $a.name; Invoke-WebRequest $a.browser_download_url -OutFile $f
    # Only run what's signed by a publisher Windows trusts (winget checks a manifest hash; we check the Authenticode signature).
    $sig = Get-AuthenticodeSignature $f
    if ($sig.Status -ne 'Valid') { throw "The downloaded $($a.name) isn't validly signed ($($sig.Status)); not running it." }
    $expected = if ($name -eq 'Git.Git') { 'Johannes Schindelin' } else { 'GitHub, Inc.' }
    if ($sig.SignerCertificate.Subject -notlike "*$expected*") { throw "The downloaded $($a.name) is signed by '$($sig.SignerCertificate.Subject)', not $expected; not running it." }
    Say "  signed by: $($sig.SignerCertificate.Subject)"
    # Both are per-machine installs, so they need the Windows admin prompt (click Yes).
    if ($name -eq 'Git.Git') { Start-Process $f -ArgumentList '/VERYSILENT','/NORESTART','/NOCANCEL' -Verb RunAs -Wait }
    else { Start-Process msiexec.exe -ArgumentList '/i',"`"$f`"",'/qn','/norestart' -Verb RunAs -Wait }
  }
  foreach ($p in @(@('Git.Git', $git), @('GitHub.cli', $gh))) {
    if (-not (Test-Path $p[1])) {
      Say "  Installing $($p[0])... (a Windows admin prompt will appear: click Yes)"
      $out = & winget.exe install -e --id $p[0] --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1
      if (-not (Test-Path $p[1])) {
        Say "  winget couldn't install $($p[0]):"; Say (($out | Select-Object -Last 3) -join "`n")
        Say "  Using the official installer instead..."
        try { Install-Official $p[0] } catch { throw "Couldn't install $($p[0]) ($($_.Exception.Message)). Run this again; if it keeps failing, ask your Tech Lead." }
        if (-not (Test-Path $p[1])) { throw "Couldn't install $($p[0]). Run this again; if it keeps failing, ask your Tech Lead." }
      }
    }
  }
  Fresh-Path
  & $gh auth status *> $null
  if ($LASTEXITCODE -ne 0) {
    Say "`n  GitHub sign-in: open https://github.com/login/device and enter the code below (it expires in 15 minutes)."
    # Through Git Bash with no input, so it prints the code and waits instead of asking to press Enter.
    & $bash -lc "'/c/Program Files/GitHub CLI/gh.exe' auth login --hostname github.com --git-protocol https --web --clipboard --scopes repo,read:org,read:packages </dev/null 2>&1"
    & $gh auth status *> $null
    if ($LASTEXITCODE -ne 0) { throw "GitHub sign-in didn't finish. Run this again to get a new code." }
  }
  & $gh auth setup-git | Out-Null
  & $gh api orgs/detail-page/memberships/$(& $gh api user -q .login) -q .state *> $null
  if ($LASTEXITCODE -ne 0) { throw "The GitHub account you're signed in as ($(& $gh api user -q .login)) isn't in DetailPage's GitHub organization. If that's the wrong account, run: gh auth logout, then run this again and sign in with your DetailPage one. If it's the right account, ask your Tech Lead for an invite, accept it, then run this again." }
  if (Test-Path (Join-Path $repo '.git')) { & $git -C $repo pull -q --ff-only 2>$null | Out-Null }
  else { Say "  Downloading the workspace..."; & $gh repo clone detail-page/engineering-workspace $repo -- -q; if ($LASTEXITCODE -ne 0) { throw "Couldn't download detail-page/engineering-workspace." } }
  # Testing an unmerged branch: set DP_WORKSPACE_BRANCH before running.
  if ($env:DP_WORKSPACE_BRANCH) {
    & $git -C $repo fetch -q origin $env:DP_WORKSPACE_BRANCH; if ($LASTEXITCODE -ne 0) { throw "Couldn't fetch branch $($env:DP_WORKSPACE_BRANCH)." }
    & $git -C $repo checkout -q -B $env:DP_WORKSPACE_BRANCH "origin/$($env:DP_WORKSPACE_BRANCH)"; if ($LASTEXITCODE -ne 0) { throw "Couldn't check out branch $($env:DP_WORKSPACE_BRANCH)." }
  }
  Say "  ok   workspace in $repo"
  $setup = Join-Path $repo 'SETUP.md'
  if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
    # Run by Claude (no keyboard): Claude carries on with the private setup.
    Say "`nNEXT (for the assistant): follow $setup. Moving into that folder shows a `"Trust this workspace?`" dialog: tell them to click Trust."
  } else {
    Say "`nDone with the first step. Open the Claude app, go to the Code tab, open the folder $repo and say: set up my workspace"
  }
}
