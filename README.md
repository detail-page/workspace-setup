# DetailPage workspace: getting started

This public repo holds only the first step of setting up a DetailPage engineering workspace. It
installs what's needed to sign in to GitHub, signs you in, and downloads the private
[engineering-workspace](https://github.com/detail-page/engineering-workspace), whose setup does the rest.
Nothing secret lives here. You need a GitHub account in the detail-page organization (ask your Tech Lead).

**Windows**: open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/detail-page/workspace-setup/main/install.ps1 | iex
```

**Mac or Linux**: open Terminal and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/detail-page/workspace-setup/main/install.sh | bash
```

**Or ask your AI assistant** (the Claude app's Code tab, or Codex):

> Set up my DetailPage workspace: run the command for my computer from https://github.com/detail-page/workspace-setup in the background, show me any link and code it prints, and then do what its last line says.
