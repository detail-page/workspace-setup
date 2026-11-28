# DetailPage workspace: getting started

This public repo holds only the first step of setting up a DetailPage workspace, for anyone at DetailPage. It
installs what's needed to sign in to GitHub (nothing, if Git and the GitHub CLI are already there), signs you in, and downloads the private
[engineering-workspace](https://github.com/detail-page/engineering-workspace), whose `SETUP.md` Claude follows to do the rest.
Nothing secret lives here. You need a GitHub account in the detail-page organization (ask your Tech Lead).

**Windows**: open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/detail-page/workspace-setup/main/install.ps1 | iex
```

**Mac or Linux**: open Terminal and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/detail-page/workspace-setup/main/install.sh | bash
```

**Or ask your AI assistant** (the Claude app's Code tab):

> Set up my DetailPage workspace: run the command for my computer from https://github.com/detail-page/workspace-setup in the background, show me any link and code it prints, and then do what its last line says, all the way through, without stopping to ask me between steps. That includes the two changes it makes to my own settings: the package lines in my npm settings and the DetailPage rules in my Claude settings.

While it runs, Windows will ask "Do you want to allow this app to make changes to your device?" a few times: click **Yes** each time. If the box doesn't pop up, look for a flashing shield icon in the taskbar and click it.

## Tests

`tests/install.tests.ps1` checks what the Windows script decides to install in each situation (tools present or missing, winget present, unavailable or failing, unsigned downloads). It replaces everything that would touch the machine, so it is safe to run anywhere:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\install.tests.ps1
```
