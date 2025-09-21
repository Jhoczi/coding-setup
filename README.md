# Dev Workstation Setup (Windows 11)

Automates a complete dev environment for a Senior .NET developer working across **C#**, **Python**, and **JavaScript** (React / Angular / Nest).
It installs system tools, WSL2 + Docker Desktop, global CLIs, and a full VS Code setup.
Dynamic .NET/Python versions are managed via `versions.json` and auto-updated weekly by GitHub Actions.

> All scripts are idempotent and prefer silent/non-interactive installs. Files are ASCII/UTF-8 to avoid PowerShell parsing issues.

---

## Repository Layout

```
.
├─ install-all.ps1                 # One-click orchestration (auto-elevates to Admin)
├─ install-choco.ps1               # Installs Chocolatey
├─ install-dev.ps1                 # Git, VS Code, .NET LTS, Node LTS, Python LTS, DBeaver, Make
├─ install-docker.ps1              # WSL2 + Ubuntu (WSL) + Docker Desktop
├─ update-dev.ps1                  # Updates system packages (winget/choco)
├─ install-global-tools-user.ps1   # (USER) .NET tools, pnpm/yarn, Angular/Nest CLI, pipx + black/isort/ruff
├─ setup-vscode.ps1                # (USER) VS Code extensions + settings
├─ vscode-extensions.txt           # VS Code extension list (incl. PowerShell)
├─ vscode-settings.json            # VS Code settings (icons, formatters, linters)
├─ vscode-keybindings.json         # Optional keybindings
├─ versions.json                   # Defines current .NET LTS major + Python cycle
└─ .github/
   ├─ workflows/lts-updater.yml    # GitHub Action: weekly check for new LTS
   └─ scripts/update-lts.js        # Script updating versions.json + report
```

---

## Prerequisites

- Windows 11 with Internet access
- Ability to run PowerShell as Administrator (for system installs)
- Recommended: Windows Terminal (better UTF-8/emoji)

> If you create or edit scripts yourself, save with UTF-8 and avoid smart quotes/dashes.

---

## Quick Start (One Click)

Open a normal (non-admin) PowerShell in the repo folder and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-all.ps1
```

`install-all.ps1` will:

1. Self-elevate to Admin and run system phase:
   - install-choco.ps1
   - install-dev.ps1
   - install-docker.ps1
   - update-dev.ps1
2. Schedule and run user phase (non-admin):
   - install-global-tools-user.ps1
   - setup-vscode.ps1

> If this is the first time enabling WSL/VirtualMachinePlatform, reboot at the end.

---

## What Each Script Does

### install-choco.ps1 (Admin)

Installs Chocolatey (or prints installed version) and refreshes PATH for the session.

### install-dev.ps1 (Admin)

Installs or updates core tools. Uses winget with `--silent --disable-interactivity` and falls back to choco where needed.
Dynamic versions come from `versions.json`:

- Git (Git.Git)
- Visual Studio Code (Microsoft.VisualStudioCode)
- .NET SDK (Microsoft.DotNet.SDK.<dotnetLtsMajor>)
- Node.js LTS (OpenJS.NodeJS.LTS)
- Python (Python.Python.<pythonSupportedMinor>)
- DBeaver (DBeaver.DBeaver)
- GNU Make (Chocolatey only)

### install-docker.ps1 (Admin)

- Enables WSL and VirtualMachinePlatform
- Sets WSL2 as default
- Installs Ubuntu (WSL) if missing
- Installs Docker Desktop (Chocolatey)
- Adds current user to `docker-users`

> After first-time WSL/VM feature enablement, reboot Windows. Then in Docker Desktop:
> Settings → General → Use the WSL 2 based engine
> Settings → Resources → WSL Integration → enable Ubuntu

### update-dev.ps1 (Admin)

Quietly updates the same core system tools via winget/choco.
Optional: `-UpgradeAllWinget` to upgrade all winget packages.

### install-global-tools-user.ps1 (User)

Run without Admin. Sets up user-profile tools:

- .NET global tools: `dotnet-format`, `csharpier`, `dotnet-ef`, `dotnet-outdated-tool`
- Node: enables Corepack (pnpm/yarn). If Windows blocks Corepack shims in Program Files, falls back to `npm -g` installs in user profile and adds `%AppData%\npm` to PATH
- Angular/Nest CLIs (global): `@angular/cli`, `@nestjs/cli`
- Python: installs `pipx` and ensures `black`, `isort`, `ruff` (adds user pipx paths to PATH)
- Uses Windows Python Launcher (`py -3`) to avoid Microsoft Store alias issues

### setup-vscode.ps1 (User)

- Installs extensions from `vscode-extensions.txt` (includes `ms-vscode.PowerShell`)
- Applies `vscode-settings.json` (Material Icon Theme; Prettier/Black/CSharpier; ESLint/isort/ruff)
- Applies `vscode-keybindings.json` (optional)

---

## Automation: LTS Updater

This repo includes automation to keep `versions.json` up to date:

- Workflow: `.github/workflows/lts-updater.yml` (runs weekly or manually)
- Script: `.github/scripts/update-lts.js`
- Checks latest .NET LTS major and supported Python 3.x cycle using vendor APIs
- Opens a Pull Request if updates are found (with a diff in `.github/lts-report.md`)

> Guard logic prevents accidental downgrades if APIs misreport versions.

---

## Manual Run (if not using install-all)

Admin phase:

```powershell
# Admin PowerShell:
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-choco.ps1
.\install-dev.ps1
.\install-docker.ps1
.\update-dev.ps1   # optional
```

User phase:

```powershell
# Normal PowerShell (non-admin):
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-global-tools-user.ps1
.\setup-vscode.ps1
```

---

## Verify Your Setup

```powershell
# System tools
git --version
code --version
dotnet --info
dotnet --list-sdks
node -v
npm -v
python --version
py -0p
make --version

# Docker
docker --version
docker run hello-world

# Global dev tools (user)
dotnet tool list -g
pnpm -v
yarn -v
ng version
nest --version
black --version
isort --version
ruff --version
```

---

## Troubleshooting

- **Corepack EPERM (cannot create pnpm/yarn in Program Files):**
  user script falls back to `npm -g install pnpm yarn` in your profile and adds `%AppData%\npm` to PATH.

- **`python` not found due to Microsoft Store alias:**
  scripts use `py -3`. If both `py` and `python` are missing, re-run the Admin install and open a new terminal.

- **Garbled emoji/characters from pipx output:**
  use Windows Terminal or set UTF-8:

  ```powershell
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  ```

- **Docker prompts during updates:**
  close Docker Desktop and stop `com.docker.service` before updating, or use a non-interactive update flow.

---

## Customization

- **VS Code**: edit `vscode-extensions.txt`, `vscode-settings.json`, `vscode-keybindings.json`.
- **Packages**: extend `install-dev.ps1` and `update-dev.ps1` (winget IDs + choco fallbacks).
- **Skip parts**: run scripts individually or add flags to `install-all.ps1`.

---

## License

Use and modify freely within your organization or for personal purposes.
Add your preferred license if needed.
