# txAdmin Tool — Installer & Updater

Automatisches Setup und Update-Tool für **txAdmin / FXServer** auf **Windows Server 2025**.

## Features

- **Installer**: FXServer + MariaDB oder MySQL vollautomatisch installieren
- **Updater**: FXServer per Klick auf die neueste Version updaten (mit Backup)
- **Dienst-Steuerung**: FXServer-Dienst starten/stoppen direkt im Tool
- **Firewall**: Alle nötigen Ports werden automatisch freigegeben
- Kein winget, kein Chocolatey — läuft nativ auf Windows Server 2025

## Schnellstart (PowerShell als Administrator)

```powershell
irm https://raw.githubusercontent.com/DEIN-USERNAME/txadmin-tool/main/txadmin-tool.ps1 | iex
```

> **Hinweis**: `DEIN-USERNAME` durch deinen GitHub-Benutzernamen ersetzen.

## Voraussetzungen

- Windows Server 2025
- PowerShell als Administrator
- Internetverbindung

## Was wird installiert?

| Komponente | Details |
|---|---|
| FXServer | Immer neueste Version vom FiveM CDN |
| MariaDB | 11.4 LTS (empfohlen) |
| MySQL | 8.4 LTS (alternativ) |
| Installationspfad | `C:\txAdmin\` |
| Datenbank | `fivem` (UTF8mb4) |
| DB-User | `fivem` |

## Nach der Installation

1. **CFX-Lizenzkey** eintragen in `C:\txAdmin\data\server.cfg`  
   → Kostenlos auf [keymaster.fivem.net](https://keymaster.fivem.net)

2. txAdmin-Panel öffnen: [http://localhost:40120](http://localhost:40120)

## Ports

| Port | Protokoll | Verwendung |
|---|---|---|
| 40120 | TCP | txAdmin Webpanel |
| 30120 | TCP + UDP | FiveM Spielserver |
| 3306 | TCP | MariaDB / MySQL |

## Update

Einfach das Tool starten → Tab "Update" → "FXServer jetzt updaten".  
Vor jedem Update wird automatisch ein Backup angelegt unter `C:\txAdmin\Backup_DATUM\`.

## Auf GitHub hochladen

```bash
git init
git add txadmin-tool.ps1 README.md
git commit -m "Initial release"
git branch -M main
git remote add origin https://github.com/DEIN-USERNAME/txadmin-tool.git
git push -u origin main
```
