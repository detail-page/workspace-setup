# DetailPage workspace bootstrap for Windows. Public on purpose: it runs before you're signed in to
# GitHub, so it can't live in the private repo. It installs winget (if missing), Git and the GitHub
# CLI, signs you in to GitHub, clones detail-page/engineering-workspace, then runs its setup.
#   irm https://raw.githubusercontent.com/detail-page/workspace-setup/main/install.ps1 | iex
& {
  # 'Continue': in Windows PowerShell 5.1, 'Stop' turns any stderr from gh/git/winget into a fatal error,
  # even when redirected. Every failure below is checked and explained explicitly instead.
  $ErrorActionPreference = 'Continue'
  Set-ExecutionPolicy -Scope Process Bypass -Force
  [Console]::OutputEncoding = [Text.Encoding]::UTF8
  $repo = Join-Path $HOME 'engineering-workspace'
  function Say($m) { Write-Host $m }
  function Fresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') + ";$env:LOCALAPPDATA\Microsoft\WindowsApps" }
  Say "`n==> DetailPage workspace: getting started"
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Say "  Installing winget (Windows' package manager)..."
    $ProgressPreference = 'SilentlyContinue'
    Install-PackageProvider -Name NuGet -Scope CurrentUser -Force | Out-Null
    Install-Module Microsoft.WinGet.Client -Scope CurrentUser -Repository PSGallery -Force | Out-Null
    Repair-WinGetPackageManager -Force -Latest | Out-Null
    Fresh-Path
  }
  $git = "$env:ProgramFiles\Git\cmd\git.exe"; $gh = "$env:ProgramFiles\GitHub CLI\gh.exe"; $bash = "$env:ProgramFiles\Git\bin\bash.exe"
  foreach ($p in @(@('Git.Git', $git), @('GitHub.cli', $gh))) {
    if (-not (Test-Path $p[1])) {
      Say "  Installing $($p[0])..."
      & winget.exe install -e --id $p[0] --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Null
      if (-not (Test-Path $p[1])) { throw "Couldn't install $($p[0]). Run this again; if it keeps failing, ask your Tech Lead." }
    }
  }
  Fresh-Path
  & $gh auth status *> $null
  if ($LASTEXITCODE -ne 0) {
    Say "`n  GitHub sign-in: open https://github.com/login/device and enter the code below (it expires in 15 minutes)."
    # Through Git Bash with no input, so it prints the code and waits instead of asking to press Enter.
    & $bash -lc "'/c/Program Files/GitHub CLI/gh.exe' auth login --hostname github.com --git-protocol https --web --scopes repo,read:org,workflow </dev/null 2>&1"
    & $gh auth status *> $null
    if ($LASTEXITCODE -ne 0) { throw "GitHub sign-in didn't finish. Run this again to get a new code." }
  }
  & $gh auth setup-git | Out-Null
  & $gh api orgs/detail-page/memberships/$(& $gh api user -q .login) -q .state *> $null
  if ($LASTEXITCODE -ne 0) { throw "Your GitHub account isn't in DetailPage's GitHub organization yet. Ask your Tech Lead for an invite, accept it, then run this again." }
  if (Test-Path (Join-Path $repo '.git')) { & $git -C $repo pull -q --ff-only 2>$null | Out-Null }
  else { Say "  Downloading the workspace..."; & $gh repo clone detail-page/engineering-workspace $repo -- -q; if ($LASTEXITCODE -ne 0) { throw "Couldn't download detail-page/engineering-workspace." } }
  Say "  ok   workspace in $repo"
  if ([Console]::IsInputRedirected -or -not [Environment]::UserInteractive) {
    # Run by a coding agent (no keyboard): the agent confirms who you are and the defaults with you.
    Say "`nNEXT (for the assistant): follow $repo\.claude\skills\workspace-setup\SKILL.md"
  } else {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'setup.ps1')
  }
}
