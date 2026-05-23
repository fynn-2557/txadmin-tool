#Requires -RunAsAdministrator
<#
.SYNOPSIS
    txAdmin All-in-One Tool - Installer & Updater
    Kompatibel mit: Windows Server 2025
    GitHub: https://github.com/DEIN-USERNAME/txadmin-tool

.USAGE
    # Direkt von GitHub ausfuehren (empfohlen):
    irm https://raw.githubusercontent.com/DEIN-USERNAME/txadmin-tool/main/txadmin-tool.ps1 | iex

    # Lokal ausfuehren:
    Set-ExecutionPolicy RemoteSigned -Scope Process -Force
    .\txadmin-tool.ps1
#>

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ============================================================
#  Konfiguration
# ============================================================
$cfg = @{
    InstallDir     = "C:\txAdmin"
    FxServerDir    = "C:\txAdmin\FXServer"
    DataDir        = "C:\txAdmin\data"
    ConfigFile     = "C:\txAdmin\data\server.cfg"
    ServiceName    = "txAdminService"
    MariadbVersion = "11.4.5"
    MysqlVersion   = "8.4.4"
    FxCdnApi       = "https://changelogs.fivem.net/servers/latest"
    FxCdnBase      = "https://runtime.fivem.net/artifacts/fivem/build_server_windows/master"
    TempDir        = "$env:TEMP\txadmin_tool"
}

# ============================================================
#  Hilfsfunktionen
# ============================================================
function Write-Log {
    param($msg, $color = "White")
    $time = Get-Date -Format "HH:mm:ss"
    $script:logBox.AppendText("[$time] $msg`r`n")
    $script:logBox.ScrollToCaret()
    $script:logBox.Refresh()
}

function Set-Status {
    param($msg)
    $script:statusLabel.Text = $msg
    $script:statusLabel.Refresh()
}

function Get-FxBuild {
    try {
        $build = (Invoke-RestMethod $cfg.FxCdnApi -UseBasicParsing).Trim()
        return $build
    } catch {
        throw "FiveM CDN nicht erreichbar: $_"
    }
}

function Get-InstalledFxBuild {
    $versionFile = "$($cfg.FxServerDir)\citizen\version.txt"
    if (Test-Path $versionFile) {
        return (Get-Content $versionFile -Raw).Trim()
    }
    return $null
}

function Download-File {
    param($url, $dest, $label)
    Write-Log "Lade $label ..."
    Write-Log "  URL: $url" 
    $wc = New-Object Net.WebClient
    $wc.DownloadFile($url, $dest)
    Write-Log "  -> Fertig: $(Split-Path $dest -Leaf)"
}

function Stop-FxService {
    $svc = Get-Service $cfg.ServiceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Log "Stoppe FXServer-Dienst..."
        Stop-Service $cfg.ServiceName -Force
        Start-Sleep 3
        Write-Log "  -> Dienst gestoppt."
    }
}

function Start-FxService {
    $svc = Get-Service $cfg.ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Log "Starte FXServer-Dienst..."
        Start-Service $cfg.ServiceName
        Start-Sleep 2
        Write-Log "  -> Dienst gestartet."
    } else {
        Write-Log "  [!] Dienst nicht gefunden - bitte zuerst installieren." 
    }
}

function Get-ServiceStatus {
    $svc = Get-Service $cfg.ServiceName -ErrorAction SilentlyContinue
    if (-not $svc)                       { return "Nicht installiert" }
    if ($svc.Status -eq "Running")       { return "Lauft" }
    if ($svc.Status -eq "Stopped")       { return "Gestoppt" }
    return $svc.Status.ToString()
}

function Update-StatusDisplay {
    $status = Get-ServiceStatus
    $build  = Get-InstalledFxBuild

    $script:svcStatusLabel.Text = "Dienst: $status"
    $script:svcStatusLabel.ForeColor = switch ($status) {
        "Lauft"             { [Drawing.Color]::FromArgb(34,197,94)  }
        "Gestoppt"          { [Drawing.Color]::FromArgb(234,179,8)  }
        "Nicht installiert" { [Drawing.Color]::FromArgb(156,163,175) }
        default             { [Drawing.Color]::FromArgb(156,163,175) }
    }

    if ($build) {
        $script:buildLabel.Text = "Installierter Build: $build"
    } else {
        $script:buildLabel.Text = "Installierter Build: -"
    }
    $script:buildLabel.Refresh()
    $script:svcStatusLabel.Refresh()
}

# ============================================================
#  INSTALLER
# ============================================================
function Start-Install {
    param($dbChoice, $dbPass)

    $script:btnInstall.Enabled = $false
    $script:btnUpdate.Enabled  = $false

    try {
        New-Item -ItemType Directory -Force -Path $cfg.TempDir    | Out-Null
        New-Item -ItemType Directory -Force -Path $cfg.FxServerDir | Out-Null
        New-Item -ItemType Directory -Force -Path $cfg.DataDir    | Out-Null

        Write-Log "=== Installation gestartet ==="

        # --- Datenbank ---
        if ($dbChoice -eq "MariaDB") {
            Install-MariaDB $dbPass
        } else {
            Install-MySQL $dbPass
        }

        # --- FXServer ---
        Install-FxServer

        # --- server.cfg ---
        if (-not (Test-Path $cfg.ConfigFile)) {
            Write-Log "Erstelle server.cfg..."
            $connStr = "mysql://fivem:$dbPass@localhost/fivem?charset=utf8mb4"
@"
# Automatisch generiert von txAdmin-Tool
endpoint_add_tcp "0.0.0.0:30120"
endpoint_add_udp "0.0.0.0:30120"

sv_maxclients 32
sv_licenseKey "cfxk_DEIN_KEY_HIER"   # <-- keymaster.fivem.net

# $dbChoice Verbindung
set mysql_connection_string "$connStr"

add_ace group.admin command allow
add_ace group.admin command.quit deny
add_principal identifier.steam:STEAM_ID group.admin
"@ | Set-Content $cfg.ConfigFile -Encoding UTF8
            Write-Log "  -> server.cfg angelegt."
        }

        # --- Firewall ---
        Set-FirewallRules $dbChoice

        # --- Dienst ---
        Register-FxService

        Write-Log ""
        Write-Log "=== Installation abgeschlossen! ==="
        Write-Log "Wichtig: CFX-Key in server.cfg eintragen!"
        Write-Log "-> $($cfg.ConfigFile)"
        Write-Log ""

        Update-StatusDisplay
        [Windows.Forms.MessageBox]::Show(
            "Installation erfolgreich!`n`nBitte CFX-Lizenzkey in`n$($cfg.ConfigFile)`neintragen.",
            "Fertig", "OK", "Information"
        ) | Out-Null

    } catch {
        Write-Log "[FEHLER] $_"
        [Windows.Forms.MessageBox]::Show("Fehler bei der Installation:`n$_", "Fehler", "OK", "Error") | Out-Null
    } finally {
        Remove-Item $cfg.TempDir -Recurse -Force -ErrorAction SilentlyContinue
        $script:btnInstall.Enabled = $true
        $script:btnUpdate.Enabled  = $true
    }
}

function Install-MariaDB {
    param($rootPass)
    Write-Log "Installiere MariaDB $($cfg.MariadbVersion)..."
    $ver = $cfg.MariadbVersion
    $url = "https://downloads.mariadb.org/rest-api/mariadb/$ver/mariadb-$ver-winx64.msi"
    $msi = "$($cfg.TempDir)\mariadb.msi"
    Download-File $url $msi "MariaDB $ver"

    $args = @("/i",$msi,"/qn",
        "INSTALLDIR=`"C:\Program Files\MariaDB\`"",
        "PORT=3306","PASSWORD=$rootPass",
        "SERVICENAME=MariaDB","DEFAULTCHARSET=utf8mb4")
    Start-Process msiexec.exe -ArgumentList $args -Wait -NoNewWindow
    Write-Log "  -> MariaDB installiert."

    $tries = 0
    while (-not (Get-Service "MariaDB" -ErrorAction SilentlyContinue) -and $tries -lt 20) {
        Start-Sleep 2; $tries++
    }
    Start-Service "MariaDB" -ErrorAction SilentlyContinue

    $mysqlExe = "C:\Program Files\MariaDB\bin\mysql.exe"
    if (Test-Path $mysqlExe) {
        & $mysqlExe -u root -p"$rootPass" --protocol=tcp -e @"
CREATE DATABASE IF NOT EXISTS fivem CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'fivem'@'localhost' IDENTIFIED BY '$rootPass';
GRANT ALL PRIVILEGES ON fivem.* TO 'fivem'@'localhost';
FLUSH PRIVILEGES;
"@
        Write-Log "  -> Datenbank 'fivem' + User 'fivem' angelegt."
    }
    $script:mysqlExePath = $mysqlExe
}

function Install-MySQL {
    param($rootPass)
    Write-Log "Installiere MySQL $($cfg.MysqlVersion)..."
    $ver   = $cfg.MysqlVersion
    $short = ($ver -split '\.')[0..1] -join '.'
    $url   = "https://dev.mysql.com/get/Downloads/MySQL-$short/mysql-$ver-winx64.msi"
    $msi   = "$($cfg.TempDir)\mysql.msi"
    Download-File $url $msi "MySQL $ver"

    $args = @("/i",$msi,"/qn",
        "INSTALLDIR=`"C:\Program Files\MySQL\MySQL Server $short\`"",
        "PORT=3306","SERVICENAME=MySQL")
    Start-Process msiexec.exe -ArgumentList $args -Wait -NoNewWindow
    Write-Log "  -> MySQL installiert."

    $tries = 0
    while (-not (Get-Service "MySQL*" -ErrorAction SilentlyContinue) -and $tries -lt 20) {
        Start-Sleep 2; $tries++
    }
    $svc = Get-Service "MySQL*" | Select-Object -First 1
    if ($svc) { Start-Service $svc.Name -ErrorAction SilentlyContinue }

    $mysqlExe = "C:\Program Files\MySQL\MySQL Server $short\bin\mysql.exe"
    $logPath  = (Get-ChildItem "$env:ProgramData\MySQL" -Recurse -Filter "*.err" -ErrorAction SilentlyContinue | Select-Object -First 1)?.FullName
    if ($logPath) {
        $tmpPass = (Select-String -Path $logPath -Pattern "temporary password.*: (.+)$").Matches.Groups[1].Value.Trim()
        if ($tmpPass -and (Test-Path $mysqlExe)) {
            & $mysqlExe -u root -p"$tmpPass" --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$rootPass'; FLUSH PRIVILEGES;"
            Write-Log "  -> MySQL root-Passwort gesetzt."
        }
    }
    if (Test-Path $mysqlExe) {
        & $mysqlExe -u root -p"$rootPass" --protocol=tcp -e @"
CREATE DATABASE IF NOT EXISTS fivem CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'fivem'@'localhost' IDENTIFIED BY '$rootPass';
GRANT ALL PRIVILEGES ON fivem.* TO 'fivem'@'localhost';
FLUSH PRIVILEGES;
"@
        Write-Log "  -> Datenbank 'fivem' + User 'fivem' angelegt."
    }
    $script:mysqlExePath = $mysqlExe
}

function Install-FxServer {
    Write-Log "Lade FXServer (neueste Version)..."
    $build  = Get-FxBuild
    $url    = "$($cfg.FxCdnBase)/$build/server.zip"
    $zip    = "$($cfg.TempDir)\fxserver.zip"
    Download-File $url $zip "FXServer Build $build"
    Write-Log "Entpacke FXServer..."
    Expand-Archive $zip -DestinationPath $cfg.FxServerDir -Force
    "$build" | Set-Content "$($cfg.FxServerDir)\citizen\version.txt" -Encoding UTF8
    Write-Log "  -> FXServer Build $build installiert."
}

function Set-FirewallRules {
    param($dbLabel)
    Write-Log "Firewall-Regeln setzen..."
    $rules = @(
        @{ Name="txAdmin-Web";       Port=40120; Proto="TCP" },
        @{ Name="FXServer-Game-TCP"; Port=30120; Proto="TCP" },
        @{ Name="FXServer-Game-UDP"; Port=30120; Proto="UDP" },
        @{ Name="DB-$dbLabel-3306";  Port=3306;  Proto="TCP" }
    )
    foreach ($r in $rules) {
        if (-not (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $r.Name -Direction Inbound `
                -Protocol $r.Proto -LocalPort $r.Port -Action Allow | Out-Null
            Write-Log "  -> $($r.Name) Port $($r.Port) freigegeben"
        } else {
            Write-Log "  -> $($r.Name) existiert bereits"
        }
    }
}

function Register-FxService {
    Write-Log "Registriere Windows-Dienst..."
    $exe = Get-ChildItem $cfg.FxServerDir -Filter "FXServer.exe" -Recurse | Select-Object -First 1
    if (-not $exe) { throw "FXServer.exe nicht gefunden!" }

    $svcArgs = "+set citizen_dir `"$($cfg.FxServerDir)\citizen`" +set txAdminDataPath `"$($cfg.DataDir)`" +exec `"$($cfg.ConfigFile)`""

    if (Get-Service $cfg.ServiceName -ErrorAction SilentlyContinue) {
        Stop-Service $cfg.ServiceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $cfg.ServiceName | Out-Null
        Start-Sleep 3
    }
    New-Service -Name $cfg.ServiceName -DisplayName "txAdmin / FXServer" `
        -BinaryPathName "`"$($exe.FullName)`" $svcArgs" `
        -StartupType Automatic | Out-Null
    Start-Service $cfg.ServiceName
    Write-Log "  -> Dienst '$($cfg.ServiceName)' registriert und gestartet."
}

# ============================================================
#  UPDATER
# ============================================================
function Start-Update {
    $script:btnInstall.Enabled = $false
    $script:btnUpdate.Enabled  = $false

    try {
        Write-Log "=== Update gestartet ==="

        $currentBuild = Get-InstalledFxBuild
        $latestBuild  = Get-FxBuild

        Write-Log "Aktuell installiert : $(if($currentBuild){"Build $currentBuild"}else{"unbekannt"})"
        Write-Log "Neueste Version     : Build $latestBuild"

        if ($currentBuild -and $currentBuild -eq $latestBuild) {
            Write-Log ""
            Write-Log "Bereits auf dem neuesten Stand!"
            [Windows.Forms.MessageBox]::Show(
                "FXServer ist bereits auf dem neuesten Stand.`nBuild: $latestBuild",
                "Kein Update noetig", "OK", "Information"
            ) | Out-Null
            return
        }

        $confirm = [Windows.Forms.MessageBox]::Show(
            "Update verfuegbar!`n`nAktuell : $(if($currentBuild){"Build $currentBuild"}else{"unbekannt"})`nNeu     : Build $latestBuild`n`nServer wird kurz gestoppt. Fortfahren?",
            "Update bestaetigen", "YesNo", "Question"
        )
        if ($confirm -ne "Yes") { Write-Log "Update abgebrochen."; return }

        New-Item -ItemType Directory -Force -Path $cfg.TempDir | Out-Null

        Stop-FxService

        Write-Log "Sichere alte Version..."
        $backupDir = "$($cfg.InstallDir)\Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $cfg.FxServerDir $backupDir -Recurse -Force
        Write-Log "  -> Backup: $backupDir"

        Write-Log "Lade FXServer Build $latestBuild..."
        $url = "$($cfg.FxCdnBase)/$latestBuild/server.zip"
        $zip = "$($cfg.TempDir)\fxserver_update.zip"
        Download-File $url $zip "FXServer Build $latestBuild"

        Write-Log "Entpacke neuen FXServer..."
        Remove-Item $cfg.FxServerDir -Recurse -Force
        Expand-Archive $zip -DestinationPath $cfg.FxServerDir -Force
        "$latestBuild" | Set-Content "$($cfg.FxServerDir)\citizen\version.txt" -Encoding UTF8
        Write-Log "  -> Build $latestBuild entpackt."

        Start-FxService

        Write-Log ""
        Write-Log "=== Update auf Build $latestBuild abgeschlossen! ==="
        Update-StatusDisplay

        [Windows.Forms.MessageBox]::Show(
            "Update erfolgreich!`nFXServer laeuft jetzt auf Build $latestBuild.",
            "Update abgeschlossen", "OK", "Information"
        ) | Out-Null

    } catch {
        Write-Log "[FEHLER] $_"
        Write-Log "Versuche, alten Build wiederherzustellen..."
        Start-FxService
        [Windows.Forms.MessageBox]::Show("Fehler beim Update:`n$_`n`nAlter Build wurde nicht veraendert.", "Fehler", "OK", "Error") | Out-Null
    } finally {
        Remove-Item $cfg.TempDir -Recurse -Force -ErrorAction SilentlyContinue
        $script:btnInstall.Enabled = $true
        $script:btnUpdate.Enabled  = $true
    }
}

# ============================================================
#  GUI AUFBAUEN
# ============================================================
$form = New-Object Windows.Forms.Form
$form.Text            = "txAdmin Tool  |  Installer & Updater"
$form.Size            = New-Object Drawing.Size(680, 620)
$form.MinimumSize     = New-Object Drawing.Size(680, 620)
$form.StartPosition   = "CenterScreen"
$form.BackColor       = [Drawing.Color]::FromArgb(15, 15, 20)
$form.ForeColor       = [Drawing.Color]::FromArgb(230, 230, 240)
$form.Font            = New-Object Drawing.Font("Segoe UI", 9)
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox     = $false

# --- Header ---
$header = New-Object Windows.Forms.Panel
$header.Size      = New-Object Drawing.Size(680, 60)
$header.Location  = New-Object Drawing.Point(0, 0)
$header.BackColor = [Drawing.Color]::FromArgb(24, 24, 32)
$form.Controls.Add($header)

$titleLabel = New-Object Windows.Forms.Label
$titleLabel.Text      = "txAdmin Tool"
$titleLabel.Font      = New-Object Drawing.Font("Segoe UI", 14, [Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [Drawing.Color]::FromArgb(139, 92, 246)
$titleLabel.Location  = New-Object Drawing.Point(16, 8)
$titleLabel.AutoSize  = $true
$header.Controls.Add($titleLabel)

$subLabel = New-Object Windows.Forms.Label
$subLabel.Text      = "Installer & Updater  |  Windows Server 2025"
$subLabel.Font      = New-Object Drawing.Font("Segoe UI", 8)
$subLabel.ForeColor = [Drawing.Color]::FromArgb(100, 100, 120)
$subLabel.Location  = New-Object Drawing.Point(18, 36)
$subLabel.AutoSize  = $true
$header.Controls.Add($subLabel)

# --- Status Bar ---
$statusBar = New-Object Windows.Forms.Panel
$statusBar.Size      = New-Object Drawing.Size(680, 36)
$statusBar.Location  = New-Object Drawing.Point(0, 60)
$statusBar.BackColor = [Drawing.Color]::FromArgb(20, 20, 28)
$form.Controls.Add($statusBar)

$script:svcStatusLabel = New-Object Windows.Forms.Label
$script:svcStatusLabel.Text      = "Dienst: ..."
$script:svcStatusLabel.Font      = New-Object Drawing.Font("Segoe UI", 9, [Drawing.FontStyle]::Bold)
$script:svcStatusLabel.ForeColor = [Drawing.Color]::FromArgb(156, 163, 175)
$script:svcStatusLabel.Location  = New-Object Drawing.Point(16, 10)
$script:svcStatusLabel.AutoSize  = $true
$statusBar.Controls.Add($script:svcStatusLabel)

$script:buildLabel = New-Object Windows.Forms.Label
$script:buildLabel.Text      = "Installierter Build: -"
$script:buildLabel.Font      = New-Object Drawing.Font("Segoe UI", 9)
$script:buildLabel.ForeColor = [Drawing.Color]::FromArgb(100, 100, 120)
$script:buildLabel.Location  = New-Object Drawing.Point(180, 10)
$script:buildLabel.AutoSize  = $true
$statusBar.Controls.Add($script:buildLabel)

$refreshBtn = New-Object Windows.Forms.Button
$refreshBtn.Text      = "↻"
$refreshBtn.Font      = New-Object Drawing.Font("Segoe UI", 11)
$refreshBtn.Size      = New-Object Drawing.Size(30, 26)
$refreshBtn.Location  = New-Object Drawing.Point(636, 5)
$refreshBtn.FlatStyle = "Flat"
$refreshBtn.FlatAppearance.BorderSize  = 0
$refreshBtn.BackColor = [Drawing.Color]::FromArgb(30, 30, 40)
$refreshBtn.ForeColor = [Drawing.Color]::FromArgb(139, 92, 246)
$refreshBtn.Cursor    = "Hand"
$refreshBtn.Add_Click({ Update-StatusDisplay })
$statusBar.Controls.Add($refreshBtn)

# --- Tab Control ---
$tabs = New-Object Windows.Forms.TabControl
$tabs.Size      = New-Object Drawing.Size(660, 400)
$tabs.Location  = New-Object Drawing.Point(10, 106)
$tabs.BackColor = [Drawing.Color]::FromArgb(15, 15, 20)
$tabs.Font      = New-Object Drawing.Font("Segoe UI", 9)
$form.Controls.Add($tabs)

# Farben fuer Tabs
$tabs.Add_DrawItem({
    param($s, $e)
    $tab = $s.TabPages[$e.Index]
    $e.Graphics.FillRectangle(
        (New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(24,24,32))),
        $e.Bounds
    )
    $selected = ($e.Index -eq $s.SelectedIndex)
    $fg = if ($selected) { [Drawing.Color]::FromArgb(139,92,246) } else { [Drawing.Color]::FromArgb(160,160,180) }
    $sf = New-Object Drawing.StringFormat
    $sf.Alignment = "Center"
    $sf.LineAlignment = "Center"
    $font = if ($selected) { New-Object Drawing.Font("Segoe UI",9,[Drawing.FontStyle]::Bold) } else { New-Object Drawing.Font("Segoe UI",9) }
    $e.Graphics.DrawString($tab.Text, $font, (New-Object Drawing.SolidBrush($fg)), $e.Bounds, $sf)
})
$tabs.DrawMode = "OwnerDrawFixed"
$tabs.ItemSize = New-Object Drawing.Size(120, 28)

# --- Tab 1: Installer ---
$tabInstall = New-Object Windows.Forms.TabPage
$tabInstall.Text      = "Installation"
$tabInstall.BackColor = [Drawing.Color]::FromArgb(15, 15, 20)
$tabInstall.ForeColor = [Drawing.Color]::FromArgb(230, 230, 240)
$tabs.TabPages.Add($tabInstall)

function New-Label { param($text,$x,$y,$w=200)
    $l = New-Object Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object Drawing.Point($x,$y)
    $l.Size = New-Object Drawing.Size($w,20)
    $l.ForeColor = [Drawing.Color]::FromArgb(160,160,180); return $l }

function New-TextBox { param($x,$y,$w=240,$pass=$false)
    $t = New-Object Windows.Forms.TextBox
    $t.Location = New-Object Drawing.Point($x,$y)
    $t.Size = New-Object Drawing.Size($w,24)
    $t.BackColor = [Drawing.Color]::FromArgb(30,30,42)
    $t.ForeColor = [Drawing.Color]::FromArgb(230,230,240)
    $t.BorderStyle = "FixedSingle"
    if ($pass) { $t.PasswordChar = '*' }
    return $t }

# DB-Auswahl
$tabInstall.Controls.Add((New-Label "Datenbank:" 16 16 120))
$dbCombo = New-Object Windows.Forms.ComboBox
$dbCombo.Items.AddRange(@("MariaDB 11.4 LTS (empfohlen)", "MySQL 8.4 LTS"))
$dbCombo.SelectedIndex = 0
$dbCombo.Location      = New-Object Drawing.Point(140, 13)
$dbCombo.Size          = New-Object Drawing.Size(240, 24)
$dbCombo.BackColor     = [Drawing.Color]::FromArgb(30, 30, 42)
$dbCombo.ForeColor     = [Drawing.Color]::FromArgb(230, 230, 240)
$dbCombo.FlatStyle     = "Flat"
$dbCombo.DropDownStyle = "DropDownList"
$tabInstall.Controls.Add($dbCombo)

# Passwort
$tabInstall.Controls.Add((New-Label "DB Root-Passwort:" 16 52 130))
$passBox1 = New-TextBox 150 49 230 $true
$tabInstall.Controls.Add($passBox1)

$tabInstall.Controls.Add((New-Label "Passwort bestätigen:" 16 82 130))
$passBox2 = New-TextBox 150 79 230 $true
$tabInstall.Controls.Add($passBox2)

# Info-Box
$infoBox = New-Object Windows.Forms.Label
$infoBox.Text = "Das Script installiert: FXServer (neueste Version), gewählte Datenbank, legt DB 'fivem' + User an, erstellt server.cfg, setzt Firewall-Regeln und registriert FXServer als Windows-Dienst."
$infoBox.Location  = New-Object Drawing.Point(16, 118)
$infoBox.Size      = New-Object Drawing.Size(620, 52)
$infoBox.ForeColor = [Drawing.Color]::FromArgb(100, 100, 120)
$infoBox.Font      = New-Object Drawing.Font("Segoe UI", 8)
$tabInstall.Controls.Add($infoBox)

$script:btnInstall = New-Object Windows.Forms.Button
$script:btnInstall.Text      = "Installation starten"
$script:btnInstall.Size      = New-Object Drawing.Size(200, 36)
$script:btnInstall.Location  = New-Object Drawing.Point(16, 180)
$script:btnInstall.FlatStyle = "Flat"
$script:btnInstall.BackColor = [Drawing.Color]::FromArgb(139, 92, 246)
$script:btnInstall.ForeColor = [Drawing.Color]::White
$script:btnInstall.Font      = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$script:btnInstall.FlatAppearance.BorderSize = 0
$script:btnInstall.Cursor    = "Hand"
$script:btnInstall.Add_Click({
    $p1 = $passBox1.Text; $p2 = $passBox2.Text
    if ($p1.Length -lt 8) {
        [Windows.Forms.MessageBox]::Show("Passwort zu kurz (mind. 8 Zeichen).","Fehler","OK","Warning") | Out-Null; return
    }
    if ($p1 -ne $p2) {
        [Windows.Forms.MessageBox]::Show("Passwoerter stimmen nicht ueberein.","Fehler","OK","Warning") | Out-Null; return
    }
    $db = if ($dbCombo.SelectedIndex -eq 0) { "MariaDB" } else { "MySQL" }
    $tabs.SelectedIndex = 2  # Log-Tab
    $job = [System.Threading.Thread]::new({ Start-Install $db $p1 })
    $job.IsBackground = $true; $job.Start()
})
$tabInstall.Controls.Add($script:btnInstall)

# --- Tab 2: Update ---
$tabUpdate = New-Object Windows.Forms.TabPage
$tabUpdate.Text      = "Update"
$tabUpdate.BackColor = [Drawing.Color]::FromArgb(15, 15, 20)
$tabUpdate.ForeColor = [Drawing.Color]::FromArgb(230, 230, 240)
$tabs.TabPages.Add($tabUpdate)

$updateInfo = New-Object Windows.Forms.Label
$updateInfo.Text = "Prueft die neueste FXServer-Version auf dem FiveM CDN.`nStopp des Dienstes → Backup → Download → Entpacken → Neustart.`n`nDie aktuell installierte Version wird vorher gesichert nach:`nC:\txAdmin\Backup_DATUM_UHRZEIT\"
$updateInfo.Location  = New-Object Drawing.Point(16, 20)
$updateInfo.Size      = New-Object Drawing.Size(620, 80)
$updateInfo.ForeColor = [Drawing.Color]::FromArgb(100, 100, 120)
$updateInfo.Font      = New-Object Drawing.Font("Segoe UI", 9)
$tabUpdate.Controls.Add($updateInfo)

$script:btnUpdate = New-Object Windows.Forms.Button
$script:btnUpdate.Text      = "FXServer jetzt updaten"
$script:btnUpdate.Size      = New-Object Drawing.Size(220, 36)
$script:btnUpdate.Location  = New-Object Drawing.Point(16, 120)
$script:btnUpdate.FlatStyle = "Flat"
$script:btnUpdate.BackColor = [Drawing.Color]::FromArgb(16, 185, 129)
$script:btnUpdate.ForeColor = [Drawing.Color]::White
$script:btnUpdate.Font      = New-Object Drawing.Font("Segoe UI", 10, [Drawing.FontStyle]::Bold)
$script:btnUpdate.FlatAppearance.BorderSize = 0
$script:btnUpdate.Cursor    = "Hand"
$script:btnUpdate.Add_Click({
    $tabs.SelectedIndex = 2
    $job = [System.Threading.Thread]::new({ Start-Update })
    $job.IsBackground = $true; $job.Start()
})
$tabUpdate.Controls.Add($script:btnUpdate)

# Dienst-Buttons
$btnStop = New-Object Windows.Forms.Button
$btnStop.Text = "Dienst stoppen"
$btnStop.Size = New-Object Drawing.Size(150,30)
$btnStop.Location = New-Object Drawing.Point(16,180)
$btnStop.FlatStyle = "Flat"
$btnStop.BackColor = [Drawing.Color]::FromArgb(234,179,8)
$btnStop.ForeColor = [Drawing.Color]::FromArgb(20,20,20)
$btnStop.FlatAppearance.BorderSize = 0
$btnStop.Cursor = "Hand"
$btnStop.Add_Click({
    $tabs.SelectedIndex = 2
    Stop-FxService
    Update-StatusDisplay
})
$tabUpdate.Controls.Add($btnStop)

$btnStart = New-Object Windows.Forms.Button
$btnStart.Text = "Dienst starten"
$btnStart.Size = New-Object Drawing.Size(150,30)
$btnStart.Location = New-Object Drawing.Point(176,180)
$btnStart.FlatStyle = "Flat"
$btnStart.BackColor = [Drawing.Color]::FromArgb(34,197,94)
$btnStart.ForeColor = [Drawing.Color]::FromArgb(10,10,10)
$btnStart.FlatAppearance.BorderSize = 0
$btnStart.Cursor = "Hand"
$btnStart.Add_Click({
    $tabs.SelectedIndex = 2
    Start-FxService
    Update-StatusDisplay
})
$tabUpdate.Controls.Add($btnStart)

$btnPanel = New-Object Windows.Forms.Button
$btnPanel.Text = "txAdmin-Panel öffnen"
$btnPanel.Size = New-Object Drawing.Size(180,30)
$btnPanel.Location = New-Object Drawing.Point(16,224)
$btnPanel.FlatStyle = "Flat"
$btnPanel.BackColor = [Drawing.Color]::FromArgb(139,92,246)
$btnPanel.ForeColor = [Drawing.Color]::White
$btnPanel.FlatAppearance.BorderSize = 0
$btnPanel.Cursor = "Hand"
$btnPanel.Add_Click({ Start-Process "http://localhost:40120" })
$tabUpdate.Controls.Add($btnPanel)

# --- Tab 3: Log ---
$tabLog = New-Object Windows.Forms.TabPage
$tabLog.Text      = "Log"
$tabLog.BackColor = [Drawing.Color]::FromArgb(15, 15, 20)
$tabs.TabPages.Add($tabLog)

$script:logBox = New-Object Windows.Forms.RichTextBox
$script:logBox.Size          = New-Object Drawing.Size(648, 356)
$script:logBox.Location      = New-Object Drawing.Point(4, 4)
$script:logBox.BackColor     = [Drawing.Color]::FromArgb(10, 10, 16)
$script:logBox.ForeColor     = [Drawing.Color]::FromArgb(180, 255, 180)
$script:logBox.Font          = New-Object Drawing.Font("Consolas", 9)
$script:logBox.ReadOnly      = $true
$script:logBox.BorderStyle   = "None"
$script:logBox.ScrollBars    = "Vertical"
$tabLog.Controls.Add($script:logBox)

# --- Status-Label unten ---
$script:statusLabel = New-Object Windows.Forms.Label
$script:statusLabel.Text      = "Bereit."
$script:statusLabel.Location  = New-Object Drawing.Point(10, 514)
$script:statusLabel.Size      = New-Object Drawing.Size(660, 20)
$script:statusLabel.ForeColor = [Drawing.Color]::FromArgb(100, 100, 120)
$script:statusLabel.Font      = New-Object Drawing.Font("Segoe UI", 8)
$form.Controls.Add($script:statusLabel)

# Footer
$footer = New-Object Windows.Forms.Label
$footer.Text      = "github.com/DEIN-USERNAME/txadmin-tool  |  Windows Server 2025"
$footer.Location  = New-Object Drawing.Point(10, 538)
$footer.Size      = New-Object Drawing.Size(660, 18)
$footer.ForeColor = [Drawing.Color]::FromArgb(60, 60, 80)
$footer.Font      = New-Object Drawing.Font("Segoe UI", 8)
$form.Controls.Add($footer)

# ============================================================
#  Start
# ============================================================
$form.Add_Shown({ Update-StatusDisplay })
[Windows.Forms.Application]::Run($form)
