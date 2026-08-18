<#
===============================================================================
 DayZ Local Server Mod Visual Manager
 Version: 1.2 (Streamlined Final Edition)
 Requires: PowerShell 5.1 + System.Windows.Forms (built into Windows 11)
 Usage: Right-click this file -> "Run with PowerShell"
===============================================================================
#>

# ==============================================================================
# Step 1: Initialize Data Folder & Path Configuration
# ==============================================================================

function Get-ScriptDirectory {
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($PSCommandPath) { return Split-Path $PSCommandPath -Parent }
    try {
        $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        return Split-Path $exePath -Parent
    } catch {}
    try {
        return Split-Path ([System.Reflection.Assembly]::GetEntryAssembly().Location) -Parent
    } catch {}
    return (Get-Location).Path
}

$ScriptDir        = Get-ScriptDirectory
$DataFolderName   = "DayZ-Local-Server-Mod-Manager-Data"
$DataFolder       = Join-Path $ScriptDir $DataFolderName
$SettingsFilePath = Join-Path $DataFolder "settings.json"

if (Test-Path -LiteralPath $SettingsFilePath -PathType Leaf) {
    $settings = Get-Content -LiteralPath $SettingsFilePath -Raw | ConvertFrom-Json
    $WorkshopPath = $settings.WorkshopPath
    $ServerPath   = $settings.ServerPath
} else {
    if (-not (Test-Path -LiteralPath $DataFolder -PathType Container)) {
        New-Item -ItemType Directory -Path $DataFolder -Force | Out-Null
    }

    $ServerPath = $ScriptDir

    $commonParent  = Split-Path $ScriptDir -Parent
    $guessWorkshop = Join-Path $commonParent "DayZ\!Workshop"
    if (Test-Path -LiteralPath $guessWorkshop -PathType Container) {
        $WorkshopPath = $guessWorkshop
    } else {
        $WorkshopPath = "Please update this path before use"
    }

    $settings = [PSCustomObject]@{
        WorkshopPath = $WorkshopPath
        ServerPath   = $ServerPath
        BatFileName  = "LocalServer.example.bat"
    }
    $json = ConvertTo-Json -InputObject $settings -Depth 2
    Set-Content -LiteralPath $SettingsFilePath -Value $json -Encoding UTF8

    Write-Host " Path configuration successful!" -ForegroundColor Green
    Write-Host " Data folder: $DataFolder" -ForegroundColor Green
    Write-Host " Config file: $SettingsFilePath" -ForegroundColor Green
    Write-Host " Default batch file: $($settings.BatFileName)" -ForegroundColor Yellow
    Write-Host " To modify, edit: $SettingsFilePath" -ForegroundColor Green
}

if (-not ([bool]$settings.PSObject.Properties['BatFileName'])) {
    $settings | Add-Member -NotePropertyName 'BatFileName' -NotePropertyValue 'LocalServer.example.bat'
    $json = ConvertTo-Json -InputObject $settings -Depth 2
    Set-Content -LiteralPath $SettingsFilePath -Value $json -Encoding UTF8
}

$BatFileName   = $settings.BatFileName
$BatFilePath   = Join-Path $ServerPath $BatFileName

$OrderFilePath    = Join-Path $DataFolder "mod_order.json"
$TypesConfigPath  = Join-Path $DataFolder "types_config.json"
$DefaultMissionPath = Join-Path $ServerPath "mpmissions\dayzOffline.chernarusplus"


# ==============================================================================
# Load WinForms Assemblies
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==============================================================================
# Create Main Form
# ==============================================================================

$Form = New-Object System.Windows.Forms.Form
$Form.Text           = "DayZ Local Server Mod Manager"
$Form.Size           = New-Object System.Drawing.Size(800, 620)
$Form.MinimumSize    = New-Object System.Drawing.Size(600, 400)
$Form.StartPosition  = "CenterScreen"
$Form.Font           = New-Object System.Drawing.Font("Segoe UI", 9)
$Form.KeyPreview     = $true

# ==============================================================================
# Global Variables
# ==============================================================================

# Store all mod names in the current list (in display order) for quick reorder operations
$Script:ModNameList = @()

# Log RichTextBox reference (assigned after GUI creation)
$Script:LogBox = $null

# Flag to suppress auto-sort in ItemCheck event (set to $true during batch operations)
$Script:SuppressItemCheckReSort = $false

# Currently selected map path in Types config page
$Script:CurrentMissionPath = $DefaultMissionPath

# Map dropdown display name -> full path index
$Script:MapDropdownIndex = @{}

# ==============================================================================
# Step 2: Core Utility Functions
# ==============================================================================

function Add-Log {
    param(
        [string]$Message,
        [string]$Color = "Black"
    )

    $null = ($Script:LogBox.SelectionStart  = $Script:LogBox.TextLength)
    $null = ($Script:LogBox.SelectionLength = 0)
    $null = ($Script:LogBox.SelectionColor  = $Color)
    $Script:LogBox.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $Message`r`n") | Out-Null
    $Script:LogBox.ScrollToCaret() | Out-Null
}

function Get-WorkshopMods {
    <#
    .SYNOPSIS
    Scans the !Workshop directory and returns folder names starting with @ (without path).
    #>
    if (-not (Test-Path -LiteralPath $WorkshopPath -PathType Container)) {
        Add-Log -Message "Workshop directory not found: $WorkshopPath" -Color "Red"
        return @()
    }
    $mods = Get-ChildItem -LiteralPath $WorkshopPath -Directory | Where-Object { $_.Name -like '@*' } | ForEach-Object { $_.Name }
    return @($mods)
}

function Read-ModOrder {
    <#
    .SYNOPSIS
    Reads custom mod order from mod_order.json. Returns empty array if missing or corrupted.
    #>
    if (-not (Test-Path -LiteralPath $OrderFilePath -PathType Leaf)) {
        return @()
    }
    try {
        $json = Get-Content -LiteralPath $OrderFilePath -Raw | ConvertFrom-Json
        return @($json)
    } catch {
        Add-Log -Message "mod_order.json is corrupted - custom sort order ignored" -Color "DarkOrange"
        return @()
    }
}

function Write-ModOrder {
    <#
    .SYNOPSIS
    Writes current mod name array to mod_order.json.
    #>
    param([string[]]$ModNames)
    $json = ConvertTo-Json -InputObject @($ModNames) -Depth 1
    Set-Content -LiteralPath $OrderFilePath -Value $json -Encoding UTF8
}

# ==============================================================================
# Types Config Utility Functions
# ==============================================================================

function Read-TypesConfig {
    <#
    .SYNOPSIS
    Reads Types config from types_config.json. Returns default structure if missing.
    #>
    if (-not (Test-Path -LiteralPath $TypesConfigPath -PathType Leaf)) {
        $config = [PSCustomObject]@{ maps = [PSCustomObject]@{}; currentMap = $DefaultMissionPath }
        $config.maps | Add-Member -NotePropertyName $DefaultMissionPath -NotePropertyValue @()
        return $config
    }
    try {
        $config = Get-Content -LiteralPath $TypesConfigPath -Raw | ConvertFrom-Json
        return $config
    } catch {
        Add-Log -Message "types_config.json is corrupted - using default config" -Color "DarkOrange"
        $config = [PSCustomObject]@{ maps = [PSCustomObject]@{}; currentMap = $DefaultMissionPath }
        $config.maps | Add-Member -NotePropertyName $DefaultMissionPath -NotePropertyValue @()
        return $config
    }
}

function Write-TypesConfigFile {
    param($ConfigObject)
    $json = ConvertTo-Json -InputObject $ConfigObject -Depth 4
    Set-Content -LiteralPath $TypesConfigPath -Value $json -Encoding UTF8
}

function Get-MapModsFromConfig {
    param($Config, [string]$MapPath)
    if ($Config.maps.PSObject.Properties.Name -contains $MapPath) {
        return @($Config.maps.PSObject.Properties[$MapPath].Value)
    }
    return @()
}

function Update-ServerDZConfig {
    param([string]$MissionFolderName)
    $cfgPath = Join-Path $ServerPath "serverDZ.cfg"
    if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) {
        Add-Log -Message "serverDZ.cfg not found - skipping template update" -Color "DarkOrange"
        return
    }
    $content = Get-Content -LiteralPath $cfgPath -Raw
    if ($content -match 'template\s*=\s*"[^"]*"') {
        $content = $content -replace 'template\s*=\s*"[^"]*"', "template=`"$MissionFolderName`""
        Set-Content -LiteralPath $cfgPath -Value $content -Encoding UTF8 -NoNewline
        Add-Log -Message "serverDZ.cfg template updated to: $MissionFolderName" -Color "Gray"
    } else {
        Add-Log -Message "No template= line found in serverDZ.cfg - skipping update" -Color "DarkOrange"
    }
}

function Update-ServerProfile {
    param([string]$MissionFolderName)
    $mapId = if ($MissionFolderName -match '\.([^.]+)$') { $matches[1] } else { $MissionFolderName }
    $profilesDir = Join-Path $ServerPath "map_profiles"
    $mapProfilePath = Join-Path $profilesDir $mapId

    if (-not (Test-Path -LiteralPath $mapProfilePath -PathType Container)) {
        New-Item -ItemType Directory -Path $mapProfilePath -Force | Out-Null
        Add-Log -Message "Created profile directory: map_profiles\$mapId" -Color "Green"
    }

    $batContent = Get-Content -LiteralPath $BatFilePath -Raw
    $relativeProfile = "map_profiles\$mapId"
    if ($batContent -match '(?m)^\s*set\s+"serverProfile=.*?"') {
        $batContent = $batContent -replace '(?m)^\s*set\s+"serverProfile=.*?"', "set `"serverProfile=$relativeProfile`""
        Set-Content -LiteralPath $BatFilePath -Value $batContent -Encoding ASCII -NoNewline
        Add-Log -Message "Profile path switched to: $relativeProfile" -Color "Green"
    } else {
        Add-Log -Message "No serverProfile line found in batch file - skipping update" -Color "DarkOrange"
    }
}

function Populate-MapDropdown {
    $config = Read-TypesConfig
    $Script:TypesMapDropdown.Items.Clear()
    $Script:MapDropdownIndex.Clear()

    # Source 1: maps already configured in types_config.json
    foreach ($mapKey in $config.maps.PSObject.Properties.Name) {
        $display = Split-Path $mapKey -Leaf
        if (-not $Script:MapDropdownIndex.ContainsKey($display)) {
            $Script:MapDropdownIndex[$display] = $mapKey
            [void]$Script:TypesMapDropdown.Items.Add($display)
        }
    }

    # Source 2: subdirectories in mpmissions that contain cfgeconomycore.xml
    $mpmissionsDir = Join-Path $ServerPath "mpmissions"
    if (Test-Path -LiteralPath $mpmissionsDir -PathType Container) {
        Get-ChildItem -LiteralPath $mpmissionsDir -Directory | ForEach-Object {
            $cfgPath = Join-Path $_.FullName "cfgeconomycore.xml"
            if (Test-Path -LiteralPath $cfgPath -PathType Leaf) {
                $display = $_.Name
                if (-not $Script:MapDropdownIndex.ContainsKey($display)) {
                    $Script:MapDropdownIndex[$display] = $_.FullName
                    [void]$Script:TypesMapDropdown.Items.Add($display)
                }
            }
        }
    }

    # Select current map
    $currentDisplay = Split-Path $config.currentMap -Leaf
    if ($Script:TypesMapDropdown.Items.Contains($currentDisplay)) {
        $Script:TypesMapDropdown.SelectedItem = $currentDisplay
    } elseif ($Script:TypesMapDropdown.Items.Count -gt 0) {
        $Script:TypesMapDropdown.SelectedIndex = 0
    }

    $Script:BtnConfirmMap.Enabled = $false
}

function Find-ModTypeFiles {
    <#
    .SYNOPSIS
    Recursively scans the specified mod directory and returns full paths of .xml files
    whose names contain "type" (case-insensitive).
    #>
    param([string]$ModName)
    $modPath = Join-Path $WorkshopPath $ModName
    if (-not (Test-Path -LiteralPath $modPath -PathType Container)) { return @() }
    $files = Get-ChildItem -LiteralPath $modPath -Recurse -File | Where-Object {
        $_.Extension -eq '.xml' -and $_.Name -match 'type'
    }
    return @($files | ForEach-Object { $_.FullName })
}

function Show-TypeFilePicker {
    <#
    .SYNOPSIS
    Opens a modal window for the user to select needed files from the scanned XML file list.
    Returns an array of selected file full paths.
    #>
    param(
        [string]$ModName,
        [string[]]$FoundFiles
    )
    if ($FoundFiles.Count -eq 0) {
        $null = [System.Windows.Forms.MessageBox]::Show("No XML files with 'type' keyword found in mod $ModName.", "Info", "OK", "Information")
        return @()
    }

    $pickerForm = New-Object System.Windows.Forms.Form
    $pickerForm.Text = "Select Types Files - $ModName"
    $pickerForm.Size = New-Object System.Drawing.Size(620, 400)
    $pickerForm.StartPosition = "CenterParent"
    $pickerForm.MinimumSize = New-Object System.Drawing.Size(400, 250)

    $pickerLabel = New-Object System.Windows.Forms.Label
    $pickerLabel.Text = "Types files found - check the ones to include:"
    $pickerLabel.AutoSize = $true
    $pickerLabel.Location = New-Object System.Drawing.Point(12, 12)

    $pickerList = New-Object System.Windows.Forms.CheckedListBox
    $pickerList.Location = New-Object System.Drawing.Point(12, 36)
    $pickerList.Size = New-Object System.Drawing.Size(580, 280)
    $pickerList.Anchor = "Top,Left,Bottom,Right"
    $pickerList.IntegralHeight = $false

    $modBasePath = (Join-Path $WorkshopPath $ModName) + "\"
    foreach ($f in $FoundFiles) {
        $relPath = if ($f.StartsWith($modBasePath)) { $f.Substring($modBasePath.Length) } else { $f }
        $idx = $pickerList.Items.Add($relPath)
        $pickerList.SetItemChecked($idx, $true)
    }

    $pickerBtnOk = New-Object System.Windows.Forms.Button
    $pickerBtnOk.Text = "OK"
    $pickerBtnOk.Size = New-Object System.Drawing.Size(80, 28)
    $pickerBtnOk.Anchor = "Bottom,Right"
    $pickerBtnOk.Location = New-Object System.Drawing.Point(430, 322)
    $pickerBtnOk.Add_Click({ $pickerForm.DialogResult = "OK"; $pickerForm.Close() })

    $pickerBtnCancel = New-Object System.Windows.Forms.Button
    $pickerBtnCancel.Text = "Cancel"
    $pickerBtnCancel.Size = New-Object System.Drawing.Size(80, 28)
    $pickerBtnCancel.Anchor = "Bottom,Right"
    $pickerBtnCancel.Location = New-Object System.Drawing.Point(512, 322)
    $pickerBtnCancel.Add_Click({ $pickerForm.DialogResult = "Cancel"; $pickerForm.Close() })

    $pickerForm.Controls.AddRange(@($pickerLabel, $pickerList, $pickerBtnOk, $pickerBtnCancel))
    $pickerForm.AcceptButton = $pickerBtnOk

    if ($pickerForm.ShowDialog() -eq "OK") {
        $selected = @()
        for ($i = 0; $i -lt $pickerList.Items.Count; $i++) {
            if ($pickerList.GetItemChecked($i)) { $selected += $FoundFiles[$i] }
        }
        return $selected
    }
    return @()
}

function Update-CfgEconomyCore {
    <#
    .SYNOPSIS
    Updates the map cfgeconomycore.xml, inserting/updating a <ce folder="ModTypes"> block
    to reference mod types files. If ModTypeFileNames is empty, removes the ModTypes
    reference block entirely.
    #>
    param(
        [string]$MissionPath,
        [string[]]$ModTypeFileNames
    )
    $cfgPath = Join-Path $MissionPath "cfgeconomycore.xml"
    if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) {
        Add-Log -Message "cfgeconomycore.xml not found: $cfgPath" -Color "Red"
        return $false
    }

    $content = Get-Content -LiteralPath $cfgPath -Raw

    # Remove existing ModTypes reference block (compatible with old and new formats)
    $content = $content -replace '(?s)\s*<ce\s+folder="\./db/ModTypes">.*?</ce>\s*', "`r`n"
    $content = $content -replace '(?s)\s*<ce\s+folder="db\\ModTypes">.*?</ce>\s*', "`r`n"
    $content = $content -replace '(?s)\s*<ce\s+folder="ModTypes">.*?</ce>\s*', "`r`n"

    # Build new block
    if ($ModTypeFileNames.Count -gt 0) {
        $ceBlock = "`r`n`t<ce folder=""./db/ModTypes"">`r`n"
        foreach ($f in $ModTypeFileNames) {
            $fileType = if ($f -match 'spawnable') { "spawnabletypes" } else { "types" }
            $ceBlock += "`t`t<file name=""$f"" type=""$fileType"" />`r`n"
        }
        $ceBlock += "`t</ce>`r`n"
        $content = $content -replace '(\s*<classes>)', "$ceBlock`$1"
    }

    try {
        Set-Content -LiteralPath $cfgPath -Value $content -Encoding UTF8 -NoNewline
        Add-Log -Message "cfgeconomycore.xml updated" -Color "Gray"
        return $true
    } catch {
        Add-Log -Message "Failed to write cfgeconomycore.xml: $($_.Exception.Message)" -Color "Red"
        return $false
    }
}

function Save-MapTypesConfig {
    <#
    .SYNOPSIS
    Saves mod types config for the specified map, updates cfgeconomycore.xml and refreshes UI.
    #>
    param([string]$MapPath, [array]$Mods)
    $config = Read-TypesConfig
    if ($config.maps.PSObject.Properties.Name -contains $MapPath) {
        $config.maps.PSObject.Properties[$MapPath].Value = [PSObject[]]$Mods
    } else {
        $config.maps | Add-Member -NotePropertyName $MapPath -NotePropertyValue ([PSObject[]]$Mods)
    }
    $config.currentMap = $MapPath
    Write-TypesConfigFile $config

    $allTypeFiles = @()
    foreach ($m in $Mods) {
        foreach ($f in $m.copiedFiles) {
            $allTypeFiles += (Split-Path $f -Leaf)
        }
    }
    Update-CfgEconomyCore -MissionPath $MapPath -ModTypeFileNames $allTypeFiles
    Sync-TypesList
}

function Sync-TypesList {
    <#
    .SYNOPSIS
    Refreshes the DataGridView and dropdowns on the Types config page.
    #>
    $config = Read-TypesConfig
    $Script:CurrentMissionPath = $config.currentMap
    $currentMods = Get-MapModsFromConfig $config $Script:CurrentMissionPath

    Populate-MapDropdown
    $Script:TypesDataGrid.Rows.Clear()

    foreach ($modEntry in $currentMods) {
        $isValid = $Script:ModNameList -contains $modEntry.modName
        foreach ($file in $modEntry.copiedFiles) {
            $leafName = Split-Path $file -Leaf
            $rowIdx = $Script:TypesDataGrid.Rows.Add($modEntry.modName, $leafName)
            if (-not $isValid) {
                $Script:TypesDataGrid.Rows[$rowIdx].DefaultCellStyle.BackColor = "LightGray"
                $Script:TypesDataGrid.Rows[$rowIdx].DefaultCellStyle.ForeColor = "DarkGray"
            }
        }
    }

    $Script:TypesDataGrid.ClearSelection()
    $selectedMod = $Script:TypesModDropdown.SelectedItem
    $Script:TypesModDropdown.Items.Clear()
    foreach ($modName in $Script:ModNameList) {
        [void]$Script:TypesModDropdown.Items.Add($modName)
    }
    if ($selectedMod -and $Script:TypesModDropdown.Items.Contains($selectedMod)) {
        $Script:TypesModDropdown.SelectedItem = $selectedMod
    } elseif ($Script:TypesModDropdown.Items.Count -gt 0) {
        $Script:TypesModDropdown.SelectedIndex = 0
    }
}

function Read-BatModList {
    <#
    .SYNOPSIS
    Parses the modList line in the batch file and returns an array of loaded mod names.
    #>
    if (-not (Test-Path -LiteralPath $BatFilePath -PathType Leaf)) {
        Add-Log -Message "Batch file not found: $BatFilePath" -Color "Red"
        return @()
    }
    $content = Get-Content -LiteralPath $BatFilePath -Raw
    if ($content -match '(?m)^\s*set\s+"modList=(-mod=.*?)"') {
        $fullParam = $matches[1]
        if ($fullParam -match '^-mod=(.*)') {
            $modListString = $matches[1]
            $mods = $modListString -split ';' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() }
            return @($mods)
        }
    }
    return @()
}

function Write-BatModList {
    <#
    .SYNOPSIS
    Updates the modList line in the batch file. All other content is left untouched.
    #>
    param([string[]]$ModNames)

    if (-not (Test-Path -LiteralPath $BatFilePath -PathType Leaf)) {
        Add-Log -Message "Batch file not found - cannot write" -Color "Red"
        return $false
    }

    $content = Get-Content -LiteralPath $BatFilePath -Raw

    $modString = ($ModNames -join ';')
    # Always append trailing semicolon for one or more mods
    if ($modString -ne '') {
        $modString += ';'
    }
    $newLine = 'set "modList=-mod=' + $modString + '"'

    # Replace the modList line
    if ($content -match '(?m)^\s*set\s+"modList=.*?"') {
        $newContent = $content -replace '(?m)^\s*set\s+"modList=.*?"', $newLine
        try {
            Set-Content -LiteralPath $BatFilePath -Value $newContent -Encoding ASCII -NoNewline
            Add-Log -Message "Batch config saved with $($ModNames.Count) mod(s) loaded" -Color "Green"
            return $true
        } catch {
            Add-Log -Message "Failed to write batch file: $($_.Exception.Message)" -Color "Red"
            return $false
        }
    } else {
        Add-Log -Message "No modList line found in batch file - cannot update" -Color "Red"
        return $false
    }
}

function Test-IsJunction {
    <#
    .SYNOPSIS
    Checks whether the given path is a Junction (directory symlink).
    #>
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $item = Get-Item -LiteralPath $Path -Force
        return ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint
    } catch {
        return $false
    }
}

function Add-ModJunction {
    <#
    .SYNOPSIS
    Creates a Junction in the DayZServer directory for a mod, pointing to the
    corresponding folder in !Workshop. Returns $true on success, $false on failure or skip.
    #>
    param([string]$ModName)

    $junctionPath = Join-Path $ServerPath $ModName
    $targetPath   = Join-Path $WorkshopPath $ModName

    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        Add-Log -Message "Target mod does not exist: $targetPath" -Color "Red"
        return $false
    }

    # Already exists
    if (Test-Path -LiteralPath $junctionPath) {
        if (Test-IsJunction $junctionPath) {
            return $true
        }
        # Physical folder with same name exists - skip
        Add-Log -Message "☠ ${ModName}: A physical folder with the same name already exists - cannot create Junction (requires manual handling)" -Color "Red"
        return $false
    }

    try {
        New-Item -ItemType Junction -Path $junctionPath -Target $targetPath -Force -ErrorAction Stop | Out-Null
        Add-Log -Message "Junction created: $ModName" -Color "Green"
        return $true
    } catch {
        Add-Log -Message "Failed to create Junction ($ModName): $($_.Exception.Message)" -Color "Red"
        return $false
    }
}

function Remove-ModJunction {
    <#
    .SYNOPSIS
    Deletes only if the path is a Junction. Physical folders are skipped.
    Returns $true on successful deletion (or if non-existent), $false on error.
    #>
    param([string]$ModName)

    $junctionPath = Join-Path $ServerPath $ModName

    if (-not (Test-Path -LiteralPath $junctionPath)) {
        return $true
    }

    if (-not (Test-IsJunction $junctionPath)) {
        Add-Log -Message "☠ ${ModName}: Physical folder, not a Junction - deletion skipped" -Color "Red"
        return $false
    }

    try {
        # rmdir removes the Junction itself without affecting the target
        cmd /c rmdir "`"$junctionPath`""
        if ($LASTEXITCODE -eq 0) {
            Add-Log -Message "Junction deleted: $ModName" -Color "DarkOrange"
            return $true
        } else {
            Add-Log -Message "Failed to delete Junction ($ModName): exit code $LASTEXITCODE" -Color "Red"
            return $false
        }
    } catch {
        Add-Log -Message "Failed to delete Junction ($ModName): $($_.Exception.Message)" -Color "Red"
        return $false
    }
}

# ==============================================================================
# Step 4: List Population & Checkbox Sync
# ==============================================================================

function Sync-ModList {
    <#
    .SYNOPSIS
    Scans !Workshop, sorts by mod_order.json, fills the CheckedListBox,
    and checks items according to the batch file configuration.
    #>

    # 1. Get all @ mods from workshop
    $workshopMods = Get-WorkshopMods
    Add-Log -Message "Found $($workshopMods.Count) mods in workshop" -Color "LightGray"

    if ($workshopMods.Count -eq 0) {
        $Script:ModListBox.Items.Clear()
        $Script:ModNameList = @()
        Add-Log -Message "No mods detected in workshop" -Color "DarkOrange"
        return
    }

    # 2. Read custom sort order
    $orderMods = Read-ModOrder

    # 3. Merge sort: known mods from order first (preserve JSON order), then append new mods
    $sorted = New-Object 'System.Collections.Generic.List[string]'
    $workshopSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in $workshopMods) { [void]$workshopSet.Add($m) }

    # Iterate custom order, keep mods still present in workshop
    foreach ($m in $orderMods) {
        if ($workshopSet.Contains($m)) {
            [void]$sorted.Add($m)
            [void] $workshopSet.Remove($m)
        }
    }

    # Append newly discovered mods (sorted by name for predictability)
    $remaining = $workshopSet | Sort-Object
    foreach ($m in $remaining) {
        [void]$sorted.Add($m)
    }

    $Script:ModNameList = @($sorted)

    # 4. Read mods loaded in batch file
    $batMods = Read-BatModList

    # 5. Populate CheckedListBox
    $Script:ModListBox.BeginUpdate()
    $Script:ModListBox.Items.Clear()
    foreach ($modName in $sorted) {
        [void] $Script:ModListBox.Items.Add($modName)
    }

    # Check items according to batch config
    $Script:SuppressItemCheckReSort = $true
    $batSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in [string[]]$batMods) { [void]$batSet.Add($m) }
    for ($i = 0; $i -lt $Script:ModListBox.Items.Count; $i++) {
        $Script:ModListBox.SetItemChecked($i, $batSet.Contains($Script:ModListBox.Items[$i].ToString()))
    }
    $Script:SuppressItemCheckReSort = $false
    $Script:ModListBox.EndUpdate()

    $checkedCount = $Script:ModListBox.CheckedItems.Count
    Add-Log -Message "Checked $checkedCount mod(s) according to local config" -Color "LightGray"

    # Clean up orphan Junctions (mod source deleted from !Workshop)
    $cleanupSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in $Script:ModNameList) { [void]$cleanupSet.Add($m) }
    $serverItems = Get-ChildItem -LiteralPath $ServerPath -Directory | Where-Object { $_.Name -like '@*' }
    foreach ($item in $serverItems) {
        $modName = $item.Name
        if (-not $cleanupSet.Contains($modName) -and (Test-IsJunction $item.FullName)) {
            if (Remove-ModJunction $modName) {
                Add-Log -Message "Cleaned up orphan Junction: $modName (source deleted)" -Color "DarkOrange"
            }
        }
    }
}

# ==============================================================================
# Step 3: Build GUI Layout
# ==============================================================================

# --- Main layout container (4 rows x 2 columns) ---
$TableLayout = New-Object System.Windows.Forms.TableLayoutPanel
$TableLayout.Dock      = "Fill"
$TableLayout.ColumnCount = 2
$TableLayout.RowCount   = 4
$TableLayout.Padding    = New-Object System.Windows.Forms.Padding(10)

[void] $TableLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))
[void] $TableLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 80)))
[void] $TableLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 48)))
[void] $TableLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent", 100)))
[void] $TableLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 40)))
[void] $TableLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 160)))

# --- Row 0: Path display area (spans 2 columns) ---
$PathPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$PathPanel.Dock          = "Fill"
$PathPanel.FlowDirection = "TopDown"
$PathPanel.AutoSize      = $true

$LabelWorkshop = New-Object System.Windows.Forms.Label
$LabelWorkshop.Text      = "Workshop source: $WorkshopPath"
$LabelWorkshop.AutoSize  = $true
$LabelWorkshop.ForeColor = "DarkSlateGray"

$LabelServer = New-Object System.Windows.Forms.Label
$LabelServer.Text      = "Server root: $ServerPath"
$LabelServer.AutoSize  = $true
$LabelServer.ForeColor = "DarkSlateGray"

$PathPanel.Controls.Add($LabelWorkshop)
$PathPanel.Controls.Add($LabelServer)
$TableLayout.Controls.Add($PathPanel, 0, 0)
$TableLayout.SetColumnSpan($PathPanel, 2)

# --- Row 1 Col 0: Mod list (CheckedListBox) ---
$Script:ModListBox = New-Object System.Windows.Forms.CheckedListBox
$Script:ModListBox.Dock          = "Fill"
$Script:ModListBox.IntegralHeight = $false
$Script:ModListBox.ItemHeight    = 22
$Script:ModListBox.CheckOnClick  = $true
$TableLayout.Controls.Add($Script:ModListBox, 0, 1)

# --- Row 1 Col 1: Sort buttons ---
$SortPanel = New-Object System.Windows.Forms.Panel
$SortPanel.Dock  = "Fill"
$SortPanel.Width = 80

$Script:BtnUp = New-Object System.Windows.Forms.Button
$Script:BtnUp.Text     = "Move Up"
$Script:BtnUp.Width    = 68
$Script:BtnUp.Height   = 30
$Script:BtnUp.Location = New-Object System.Drawing.Point(6, 0)

$Script:BtnDown = New-Object System.Windows.Forms.Button
$Script:BtnDown.Text     = "Move Dn"
$Script:BtnDown.Width    = 68
$Script:BtnDown.Height   = 30
$Script:BtnDown.Location = New-Object System.Drawing.Point(6, 35)

$HintLabel = New-Object System.Windows.Forms.Label
$HintLabel.Text      = "Ctrl+↑↓"
$HintLabel.Width     = 68
$HintLabel.Height    = 16
$HintLabel.Location  = New-Object System.Drawing.Point(6, 68)
$HintLabel.ForeColor = "DarkGray"
$HintLabel.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5)
$HintLabel.TextAlign = "MiddleCenter"

$SortPanel.Controls.Add($Script:BtnUp)
$SortPanel.Controls.Add($Script:BtnDown)
$SortPanel.Controls.Add($HintLabel)
$TableLayout.Controls.Add($SortPanel, 1, 1)

# --- Row 2: Action button area (spans 2 columns) ---
$BtnPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$BtnPanel.Dock          = "Fill"
$BtnPanel.FlowDirection = "LeftToRight"
$BtnPanel.Padding       = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)

$Script:BtnRefresh = New-Object System.Windows.Forms.Button
$Script:BtnRefresh.Text   = "Refresh"
$Script:BtnRefresh.Width  = 90
$Script:BtnRefresh.Height = 28

$Script:BtnSelectAll = New-Object System.Windows.Forms.Button
$Script:BtnSelectAll.Text   = "Select All"
$Script:BtnSelectAll.Width  = 90
$Script:BtnSelectAll.Height = 28

$Script:BtnComplete = New-Object System.Windows.Forms.Button
$Script:BtnComplete.Text      = "Start Game"
$Script:BtnComplete.Width     = 100
$Script:BtnComplete.Height    = 28
$Script:BtnComplete.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 50)
$Script:BtnComplete.ForeColor = "White"
$Script:BtnComplete.FlatStyle = "Flat"
$Script:BtnComplete.UseVisualStyleBackColor = $false
$Script:BtnComplete.FlatAppearance.BorderSize = 0

$BtnPanel.Controls.Add($Script:BtnRefresh)
$BtnPanel.Controls.Add($Script:BtnSelectAll)
$BtnPanel.Controls.Add($Script:BtnComplete)
$TableLayout.Controls.Add($BtnPanel, 0, 2)
$TableLayout.SetColumnSpan($BtnPanel, 2)

# --- Row 3: Log area (spans 2 columns) ---
$LogBoxCtrl = New-Object System.Windows.Forms.RichTextBox
$LogBoxCtrl.Dock        = "Fill"
$LogBoxCtrl.ReadOnly    = $true
$LogBoxCtrl.BackColor   = [System.Drawing.Color]::FromArgb(30, 30, 30)
$LogBoxCtrl.ForeColor   = "LightGray"
$LogBoxCtrl.Font        = New-Object System.Drawing.Font("Consolas", 8.5)
$LogBoxCtrl.WordWrap    = $true
$LogBoxCtrl.BorderStyle = "FixedSingle"
$TableLayout.Controls.Add($LogBoxCtrl, 0, 3)
$TableLayout.SetColumnSpan($LogBoxCtrl, 2)

# ==============================================================================
# Build TabControl (Mod Manager page + Map Config page)
# ==============================================================================

$TabControl = New-Object System.Windows.Forms.TabControl
$TabControl.Dock = "Fill"

# --- Tab 1: Mod Manager page (contains all existing layout) ---
$ModTabPage = New-Object System.Windows.Forms.TabPage
$ModTabPage.Text = "Mod Manager"
$ModTabPage.Controls.Add($TableLayout)

# --- Tab 2: Map Config page ---
$Script:TypesPage = New-Object System.Windows.Forms.TabPage
$Script:TypesPage.Text = "Map Config"
$Script:TypesPage.Padding = New-Object System.Windows.Forms.Padding(10)

$TypesLayout = New-Object System.Windows.Forms.TableLayoutPanel
$TypesLayout.Dock = "Fill"
$TypesLayout.ColumnCount = 1
$TypesLayout.RowCount = 5
[void]$TypesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 36)))
[void]$TypesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 42)))
[void]$TypesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent", 100)))
[void]$TypesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 45)))
[void]$TypesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 22)))

# Row 0: Map selection bar
$TypesTopPanel = New-Object System.Windows.Forms.TableLayoutPanel
$TypesTopPanel.Dock = "Fill"
$TypesTopPanel.ColumnCount = 4
[void]$TypesTopPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 85)))
[void]$TypesTopPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 260)))
[void]$TypesTopPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 90)))
[void]$TypesTopPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))

$TypesMapCaption = New-Object System.Windows.Forms.Label
$TypesMapCaption.Text = "Current Map:"
$TypesMapCaption.AutoSize = $true
$TypesMapCaption.TextAlign = "MiddleLeft"

$Script:TypesMapDropdown = New-Object System.Windows.Forms.ComboBox
$Script:TypesMapDropdown.Dock = "Fill"
$Script:TypesMapDropdown.DropDownStyle = "DropDownList"
$Script:TypesMapDropdown.Height = 28

$Script:BtnConfirmMap = New-Object System.Windows.Forms.Button
$Script:BtnConfirmMap.Text = "Apply"
$Script:BtnConfirmMap.Dock = "Fill"
$Script:BtnConfirmMap.Height = 28
$Script:BtnConfirmMap.Enabled = $false

$TypesTopPanel.Controls.Add($TypesMapCaption, 0, 0)
$TypesTopPanel.Controls.Add($Script:TypesMapDropdown, 1, 0)
$TypesTopPanel.Controls.Add($Script:BtnConfirmMap, 2, 0)
$TypesLayout.Controls.Add($TypesTopPanel, 0, 0)

# Row 1: Action area (mod selection + Config XML button)
$TypesActionPanel = New-Object System.Windows.Forms.TableLayoutPanel
$TypesActionPanel.Dock = "Fill"
$TypesActionPanel.ColumnCount = 4
[void]$TypesActionPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 85)))
[void]$TypesActionPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 260)))
[void]$TypesActionPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 90)))
[void]$TypesActionPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))
$TypesActionPanel.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)

$TypesModCaption = New-Object System.Windows.Forms.Label
$TypesModCaption.Text = "Mod Config:"
$TypesModCaption.Dock = "Fill"
$TypesModCaption.AutoSize = $false
$TypesModCaption.TextAlign = "MiddleLeft"

$Script:TypesModDropdown = New-Object System.Windows.Forms.ComboBox
$Script:TypesModDropdown.Dock = "Fill"
$Script:TypesModDropdown.DropDownStyle = "DropDownList"
$Script:TypesModDropdown.Height = 28

$Script:BtnConfigXml = New-Object System.Windows.Forms.Button
$Script:BtnConfigXml.Text = "Config XML"
$Script:BtnConfigXml.Width = 90
$Script:BtnConfigXml.Height = 28

$TypesActionPanel.Controls.Add($TypesModCaption, 0, 0)
$TypesActionPanel.Controls.Add($Script:TypesModDropdown, 1, 0)
$TypesActionPanel.Controls.Add($Script:BtnConfigXml, 2, 0)
$TypesLayout.Controls.Add($TypesActionPanel, 0, 1)

# Row 2: DataGridView (mods with types configured)
$Script:TypesDataGrid = New-Object System.Windows.Forms.DataGridView
$Script:TypesDataGrid.Dock = "Fill"
$Script:TypesDataGrid.AllowUserToAddRows = $false
$Script:TypesDataGrid.AllowUserToDeleteRows = $false
$Script:TypesDataGrid.AllowUserToResizeRows = $false
$Script:TypesDataGrid.AllowUserToResizeColumns = $false
$Script:TypesDataGrid.ColumnHeadersHeightSizeMode = "DisableResizing"
$Script:TypesDataGrid.ReadOnly = $true
$Script:TypesDataGrid.SelectionMode = "FullRowSelect"
$Script:TypesDataGrid.RowHeadersVisible = $false
$Script:TypesDataGrid.BackgroundColor = [System.Drawing.Color]::White
$Script:TypesDataGrid.BorderStyle = "FixedSingle"
$Script:TypesDataGrid.AutoSizeColumnsMode = "Fill"

$colModName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colModName.HeaderText = "Mod Name"
$colModName.FillWeight = 50
[void]$Script:TypesDataGrid.Columns.Add($colModName)

$colFiles = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colFiles.HeaderText = "Types Files"
$colFiles.FillWeight = 50
[void]$Script:TypesDataGrid.Columns.Add($colFiles)

$TypesLayout.Controls.Add($Script:TypesDataGrid, 0, 2)

# Row 3: Bottom action bar (Remove Selected / Clean Invalid)
$TypesBottomPanel = New-Object System.Windows.Forms.TableLayoutPanel
$TypesBottomPanel.Dock = "Fill"
$TypesBottomPanel.ColumnCount = 3
[void]$TypesBottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 100)))
[void]$TypesBottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))
[void]$TypesBottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 100)))

$Script:BtnRemoveSelected = New-Object System.Windows.Forms.Button
$Script:BtnRemoveSelected.Text = "Remove Selected"
$Script:BtnRemoveSelected.Dock = "Fill"
$Script:BtnRemoveSelected.Height = 30

$Script:BtnClearInvalid = New-Object System.Windows.Forms.Button
$Script:BtnClearInvalid.Text = "Clean Invalid"
$Script:BtnClearInvalid.Dock = "Fill"
$Script:BtnClearInvalid.Height = 30

$TypesBottomPanel.Controls.Add($Script:BtnRemoveSelected, 0, 0)
$TypesBottomPanel.Controls.Add($Script:BtnClearInvalid, 2, 0)
$TypesLayout.Controls.Add($TypesBottomPanel, 0, 3)

# Row 4: Hint text
$TypesHintLabel = New-Object System.Windows.Forms.Label
$TypesHintLabel.Text = "Note: 3rd-party map mission folders must be manually placed in mpmissions. Gray rows indicate invalid mods."
$TypesHintLabel.Dock = "Fill"
$TypesHintLabel.ForeColor = "DarkGray"
$TypesHintLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$TypesHintLabel.TextAlign = "MiddleLeft"
$TypesHintLabel.Padding = New-Object System.Windows.Forms.Padding(2, 0, 0, 0)
$TypesLayout.Controls.Add($TypesHintLabel, 0, 4)

$Script:TypesPage.Controls.Add($TypesLayout)

# --- Assemble TabControl and attach to form ---
[void]$TabControl.TabPages.Add($ModTabPage)
[void]$TabControl.TabPages.Add($Script:TypesPage)
$Form.Controls.Add($TabControl)

# Bind log control reference to global variable for Add-Log use
$Script:LogBox = $LogBoxCtrl

# ==============================================================================
# Step 5: Event Handlers
# ==============================================================================

# Helper: swap two adjacent items in CheckedListBox (internal operation, preserves check state)
function Swap-CheckedItem {
    param([int]$Index, [int]$Offset)
    if ($Script:ModListBox.Items.Count -eq 0) { return }
    $otherIdx = $Index + $Offset
    if ($otherIdx -lt 0 -or $otherIdx -ge $Script:ModListBox.Items.Count) { return }

    # Only allow swapping within same check group (checked / unchecked separately)
    if ($Script:ModListBox.GetItemChecked($Index) -ne $Script:ModListBox.GetItemChecked($otherIdx)) { return }

    # Swap display list
    $itemA      = $Script:ModListBox.Items[$Index]
    $itemB      = $Script:ModListBox.Items[$otherIdx]
    $checkedA   = $Script:ModListBox.GetItemChecked($Index)
    $checkedB   = $Script:ModListBox.GetItemChecked($otherIdx)

    $Script:ModListBox.Items[$Index]    = $itemB
    $Script:ModListBox.Items[$otherIdx] = $itemA
    $Script:ModListBox.SetItemChecked($Index, $checkedB)
    $Script:ModListBox.SetItemChecked($otherIdx, $checkedA)
    $Script:ModListBox.SelectedIndex = $otherIdx

    # Sync ModNameList
    $temp = $Script:ModNameList[$Index]
    $Script:ModNameList[$Index]    = $Script:ModNameList[$otherIdx]
    $Script:ModNameList[$otherIdx] = $temp
}

# --- Refresh List ---
$Script:BtnRefresh.Add_Click({
    Sync-ModList
})

# --- Select All / Deselect All ---
$Script:BtnSelectAll.Add_Click({
    if ($Script:ModListBox.Items.Count -eq 0) { return }

    $allChecked = $true
    for ($i = 0; $i -lt $Script:ModListBox.Items.Count; $i++) {
        if (-not $Script:ModListBox.GetItemChecked($i)) {
            $allChecked = $false
            break
        }
    }

    $newState = -not $allChecked
    $Script:SuppressItemCheckReSort = $true
    $Script:ModListBox.BeginUpdate()
    for ($i = 0; $i -lt $Script:ModListBox.Items.Count; $i++) {
        $Script:ModListBox.SetItemChecked($i, $newState)
    }
    $Script:ModListBox.EndUpdate()
    $Script:SuppressItemCheckReSort = $false

    $Script:BtnSelectAll.Text = if ($newState) { "Deselect All" } else { "Select All" }
})

# --- Move Up ---
$Script:BtnUp.Add_Click({
    $idx = $Script:ModListBox.SelectedIndex
    if ($idx -le 0) { return }
    Swap-CheckedItem -Index $idx -Offset -1
})

# --- Move Down ---
$Script:BtnDown.Add_Click({
    $idx = $Script:ModListBox.SelectedIndex
    if ($idx -lt 0 -or $idx -ge $Script:ModListBox.Items.Count - 1) { return }
    Swap-CheckedItem -Index $idx -Offset 1
})

# --- Keyboard shortcuts Ctrl+Up / Ctrl+Down ---
$Form.Add_KeyDown({
    if ($_.Control) {
        if ($_.KeyCode -eq "Up") {
            $Script:BtnUp.PerformClick()
            $_.SuppressKeyPress = $true
        }
        elseif ($_.KeyCode -eq "Down") {
            $Script:BtnDown.PerformClick()
            $_.SuppressKeyPress = $true
        }
    }
})

# --- Auto-group on check: checked items first, unchecked items after ---
$Script:ModListBox.Add_ItemCheck({
    param($sender, $e)

    if ($Script:SuppressItemCheckReSort) { return }

    $Script:PendingCheckItemName = $Script:ModListBox.Items[$e.Index].ToString()

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1
    $timer.Add_Tick({
        $this.Stop()
        $this.Dispose()

        $Script:SuppressItemCheckReSort = $true

        if ($Script:ModListBox.Items.Count -eq 0) {
            $Script:SuppressItemCheckReSort = $false
            return
        }

        $checkedList = New-Object 'System.Collections.Generic.List[string]'
        $uncheckedList = New-Object 'System.Collections.Generic.List[string]'

        $Script:ModListBox.BeginUpdate()
        for ($i = 0; $i -lt $Script:ModListBox.Items.Count; $i++) {
            $name = $Script:ModListBox.Items[$i].ToString()
            if ($Script:ModListBox.GetItemChecked($i)) {
                $checkedList.Add($name)
            } else {
                $uncheckedList.Add($name)
            }
        }

        $newOrder = @($checkedList) + @($uncheckedList)

        $Script:ModListBox.Items.Clear()
        foreach ($name in $newOrder) {
            [void]$Script:ModListBox.Items.Add($name)
        }

        for ($i = 0; $i -lt $Script:ModListBox.Items.Count; $i++) {
            $Script:ModListBox.SetItemChecked($i, $i -lt $checkedList.Count)
        }

        $Script:ModNameList = @($newOrder)

        if ($Script:PendingCheckItemName) {
            for ($idx = 0; $idx -lt $Script:ModListBox.Items.Count; $idx++) {
                if ($Script:ModListBox.Items[$idx].ToString() -eq $Script:PendingCheckItemName) {
                    $Script:ModListBox.SelectedIndex = $idx
                    break
                }
            }
        }

        $Script:ModListBox.EndUpdate()
        $Script:SuppressItemCheckReSort = $false

        $allChecked = $true
        for ($ci = 0; $ci -lt $Script:ModListBox.Items.Count; $ci++) {
            if (-not $Script:ModListBox.GetItemChecked($ci)) {
                $allChecked = $false
                break
            }
        }
        $Script:BtnSelectAll.Text = if ($allChecked) { "Deselect All" } else { "Select All" }
    })
    $timer.Start()
})

# ==============================================================================
# Step 6: [Apply] Button - Commit All Operations
# ==============================================================================

$Script:BtnComplete.Add_Click({
    if ($Script:ModListBox.Items.Count -eq 0) {
        Add-Log -Message "List is empty - nothing to do" -Color "DarkOrange"
        return
    }

    $Script:BtnComplete.Enabled = $false
    $Script:BtnComplete.Text    = "Processing..."

    $Form.Refresh()

    try {
        # --- 1. Collect current state ---
        $allModsInOrder = @($Script:ModNameList)
        $checkedMods = New-Object 'System.Collections.Generic.List[string]'
        for ($i = 0; $i -lt $Script:ModListBox.Items.Count; $i++) {
            if ($Script:ModListBox.GetItemChecked($i)) {
                $checkedMods.Add($Script:ModListBox.Items[$i].ToString())
            }
        }

        Add-Log -Message "==================== Operation Summary ====================" -Color "Cyan"

        # --- Preflight validation ---
        Add-Log -Message "Preflight: validating environment..." -Color "Gray"

        if (-not (Test-Path -LiteralPath $WorkshopPath -PathType Container)) {
            throw "[PREFLIGHT] Workshop directory not found: $WorkshopPath"
        }
        if (-not (Test-Path -LiteralPath $BatFilePath -PathType Leaf)) {
            throw "[PREFLIGHT] Batch file not found: $BatFilePath"
        }
        $batContent = Get-Content -LiteralPath $BatFilePath -Raw
        if ($batContent -notmatch '(?m)set\s+"modList=') {
            throw "[PREFLIGHT] Batch file does not contain a modList line"
        }
        $missingMods = @($checkedMods | Where-Object { -not (Test-Path -LiteralPath (Join-Path $WorkshopPath $_) -PathType Container) })
        if ($missingMods.Count -gt 0) {
            throw "[PREFLIGHT] Mod(s) not found in Workshop: $($missingMods -join ', ')"
        }

        Add-Log -Message "Preflight checks passed" -Color "Green"

        # --- 2. Update batch file ---
        if (-not (Write-BatModList -ModNames $checkedMods)) {
            throw "[ERROR] Failed to update batch file. No Junction changes were made."
        }

        # --- 3. Save mod order to mod_order.json ---
        Write-ModOrder -ModNames $allModsInOrder

        # --- 4. Sync Junctions ---
        $createdCount  = 0
        $deletedCount  = 0
        $skippedCount  = 0
        $checkedSet = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($m in [string[]]$checkedMods) { [void]$checkedSet.Add($m) }

        foreach ($modName in $allModsInOrder) {
            if ($checkedSet.Contains($modName)) {
                $junctionPath = Join-Path $ServerPath $modName
                if (Test-Path -LiteralPath $junctionPath) {
                    if (Test-IsJunction $junctionPath) {
                        $skippedCount++
                    } else {
                        Add-Log -Message "☠ ${modName}: A physical folder with the same name already exists - cannot create Junction (requires manual handling)" -Color "Red"
                        $skippedCount++
                    }
                } else {
                    if (Add-ModJunction $modName) { $createdCount++ }
                    else { $skippedCount++ }
                }
            } else {
                $junctionPath = Join-Path $ServerPath $modName
                if (Test-Path -LiteralPath $junctionPath) {
                    if (Remove-ModJunction $modName) { $deletedCount++ }
                    else { $skippedCount++ }
                } else {
                    $skippedCount++
                }
            }
        }

        # --- 5. Junction check: checked but link missing ---
        foreach ($modName in $checkedMods) {
            $junctionPath = Join-Path $ServerPath $modName
            if (-not (Test-IsJunction $junctionPath)) {
                Add-Log -Message "⚠ $modName is checked but its Junction does not exist!" -Color "Red"
            }
        }

        # --- 6. Summary ---
        Add-Log -Message "Junctions created: $createdCount / deleted: $deletedCount / skipped: $skippedCount" -Color "LightGray"

        $typesConfig = Read-TypesConfig
        $currentMapMods = Get-MapModsFromConfig $typesConfig $typesConfig.currentMap
        $configuredCount = $currentMapMods.Count
        $skipLaunch = $false
        if ($configuredCount -gt 0) {
            $checkedConfigured = 0
            $uncheckedConfigured = @()
            foreach ($m in $currentMapMods) {
                if ($checkedMods -contains $m.modName) {
                    $checkedConfigured++
                } else {
                    $uncheckedConfigured += $m.modName
                }
            }
            Add-Log -Message "Types config: $configuredCount mod(s) with types configured, $checkedConfigured checked" -Color "LightGray"
            if ($uncheckedConfigured.Count -gt 0) {
                $names = ($uncheckedConfigured -join ', ')
                Add-Log -Message "Mods with types configured but not checked: $names" -Color "Red"
                $skipLaunch = $true
            }
        }
        Add-Log -Message "==================================================" -Color "Cyan"

        # --- 7. Launch server and game ---
        if ($skipLaunch) {
            Add-Log -Message "Missing types config detected - launch skipped" -Color "DarkOrange"
        } else {
            Start-Process -FilePath $BatFilePath -WorkingDirectory $ServerPath
            Add-Log -Message "Batch launched - DayZ will start via Steam - This window will close in 3 minutes..." -Color "Cyan"

            $closeTimer = New-Object System.Windows.Forms.Timer
            $closeTimer.Interval = 180000
            $closeTimer.Add_Tick({
                $this.Stop()
                $this.Dispose()
                $Form.Close()
            })
            $closeTimer.Start()
        }

    } catch {
        Add-Log -Message "Operation failed: $($_.Exception.Message)" -Color "Red"
    } finally {
        $Script:BtnComplete.Enabled = $true
        $Script:BtnComplete.Text    = "Start Game"
    }
})

# ==============================================================================
# Step 7: Types Config Page Event Handlers
# ==============================================================================

$TabControl.Add_SelectedIndexChanged({
    if ($TabControl.SelectedTab -eq $Script:TypesPage) {
        Sync-TypesList
    }
})

# --- Map Config Page ---

# --- Apply map change (dropdown confirmation) ---
$Script:BtnConfirmMap.Add_Click({
    $selected = $Script:TypesMapDropdown.SelectedItem
    if (-not $selected) {
        Add-Log -Message "Please select a map from the dropdown first" -Color "DarkOrange"
        return
    }
    $newPath = $Script:MapDropdownIndex[$selected.ToString()]
    $cfgPath = Join-Path $newPath "cfgeconomycore.xml"
    if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) {
        $null = [System.Windows.Forms.MessageBox]::Show("cfgeconomycore.xml not found in the selected map directory - please try another.", "Invalid Path", "OK", "Warning")
        return
    }
    $Script:CurrentMissionPath = $newPath
    $config = Read-TypesConfig
    $config.currentMap = $newPath
    Write-TypesConfigFile $config

    $missionFolderName = Split-Path $newPath -Leaf
    Update-ServerDZConfig -MissionFolderName $missionFolderName
    Update-ServerProfile -MissionFolderName $missionFolderName

    Sync-TypesList
    Add-Log -Message "Map switched to: $($Script:CurrentMissionPath)" -Color "Green"
})

# --- Map dropdown selection changed ---
$Script:TypesMapDropdown.Add_SelectedIndexChanged({
    $selected = $Script:TypesMapDropdown.SelectedItem
    if ($selected) {
        $mapPath = $Script:MapDropdownIndex[$selected.ToString()]
        $Script:BtnConfirmMap.Enabled = ($mapPath -ne $Script:CurrentMissionPath)
    }
})

# --- Config XML ---
$Script:BtnConfigXml.Add_Click({
    $modName = $Script:TypesModDropdown.SelectedItem
    if (-not $modName) {
        Add-Log -Message "Please select a mod from the dropdown first" -Color "DarkOrange"
        return
    }

    Add-Log -Message "Scanning $modName for types files..." -Color "LightGray"
    $foundFiles = Find-ModTypeFiles -ModName $modName
    Add-Log -Message "Found $($foundFiles.Count) candidate file(s)" -Color "LightGray"

    $selectedFiles = Show-TypeFilePicker -ModName $modName -FoundFiles $foundFiles
    if ($selectedFiles.Count -eq 0) {
        Add-Log -Message "Configuration cancelled" -Color "Gray"
        return
    }

    $missionPath = $Script:CurrentMissionPath
    $modTypesDir = Join-Path $missionPath "db\ModTypes"
    if (-not (Test-Path -LiteralPath $modTypesDir -PathType Container)) {
        New-Item -ItemType Directory -Path $modTypesDir -Force | Out-Null
    }

    $config = Read-TypesConfig
    $mods = Get-MapModsFromConfig $config $missionPath

    # Remove old config for this mod
    $oldEntry = $mods | Where-Object { $_.modName -eq $modName }
    if ($oldEntry) {
        foreach ($oldFile in $oldEntry.copiedFiles) {
            $oldPath = Join-Path $missionPath $oldFile
            if (Test-Path -LiteralPath $oldPath) {
                Remove-Item -LiteralPath $oldPath -Force
                Add-Log -Message "Deleted old file: $oldFile" -Color "Gray"
            }
        }
        $mods = @($mods | Where-Object { $_.modName -ne $modName })
    }

    $copiedFiles = @()
    $modBasePath = Join-Path $WorkshopPath $modName
    foreach ($srcFile in $selectedFiles) {
        $relPath = $srcFile.Substring($modBasePath.Length + 1)
        $safeRelName = $relPath -replace '[\\/]', '_'
        $cleanModName = $modName -replace '^@', ''
        $destName = "${cleanModName}_$safeRelName"
        $destPath = Join-Path $modTypesDir $destName
        Copy-Item -LiteralPath $srcFile -Destination $destPath -Force
        $copiedFiles += "db\ModTypes\$destName"
        Add-Log -Message "Copied: $destName" -Color "Green"
    }

    $newEntry = @{
        modName     = $modName
        copiedFiles = @($copiedFiles)
    }
    $mods += $newEntry
    Save-MapTypesConfig -MapPath $missionPath -Mods $mods
    Add-Log -Message "$modName types configuration completed" -Color "Green"
})

# --- Remove Selected ---
$Script:BtnRemoveSelected.Add_Click({
    $selectedRows = $Script:TypesDataGrid.SelectedRows
    if ($selectedRows.Count -eq 0) {
        Add-Log -Message "Please select rows to remove in the table first" -Color "DarkOrange"
        return
    }

    $missionPath = $Script:CurrentMissionPath
    $config = Read-TypesConfig
    $mods = Get-MapModsFromConfig $config $missionPath

    $toRemove = @{}
    foreach ($row in $selectedRows) {
        $modName = $row.Cells[0].Value.ToString()
        $leafName = $row.Cells[1].Value.ToString()
        if (-not $toRemove.ContainsKey($modName)) {
            $toRemove[$modName] = New-Object 'System.Collections.Generic.List[string]'
        }
        [void]$toRemove[$modName].Add($leafName)
    }

    foreach ($modName in $toRemove.Keys) {
        $entry = $mods | Where-Object { $_.modName -eq $modName }
        if (-not $entry) { continue }
        foreach ($leafName in $toRemove[$modName]) {
            $matchFile = $entry.copiedFiles | Where-Object { (Split-Path $_ -Leaf) -eq $leafName }
            if (-not $matchFile) { continue }
            $filePath = Join-Path $missionPath $matchFile
            if (Test-Path -LiteralPath $filePath) {
                Remove-Item -LiteralPath $filePath -Force
                Add-Log -Message "Deleted: $leafName" -Color "DarkOrange"
            }
            $entry.copiedFiles = @($entry.copiedFiles | Where-Object { $_ -ne $matchFile })
        }
        if ($entry.copiedFiles.Count -eq 0) {
            $mods = @($mods | Where-Object { $_.modName -ne $modName })
            Add-Log -Message "Removed $modName types config (no files remaining)" -Color "DarkOrange"
        }
    }

    Save-MapTypesConfig -MapPath $missionPath -Mods $mods
})

# --- Clean Invalid ---
$Script:BtnClearInvalid.Add_Click({
    $missionPath = $Script:CurrentMissionPath
    $config = Read-TypesConfig
    $mods = Get-MapModsFromConfig $config $missionPath
    if ($mods.Count -eq 0) {
        Add-Log -Message "No types configuration present" -Color "DarkOrange"
        return
    }

    $invalidMods = @($mods | Where-Object { $Script:ModNameList -notcontains $_.modName })
    if ($invalidMods.Count -eq 0) {
        Add-Log -Message "No invalid types configurations" -Color "LightGray"
        return
    }

    foreach ($entry in $invalidMods) {
        foreach ($file in $entry.copiedFiles) {
            $filePath = Join-Path $missionPath $file
            if (Test-Path -LiteralPath $filePath) {
                Remove-Item -LiteralPath $filePath -Force
                Add-Log -Message "Deleted: $(Split-Path $file -Leaf) (mod $($entry.modName) is invalid)" -Color "DarkOrange"
            }
        }
        Add-Log -Message "Cleaned up $($entry.modName) types config (mod is invalid)" -Color "DarkOrange"
    }
    $mods = @($mods | Where-Object { $Script:ModNameList -contains $_.modName })
    Save-MapTypesConfig -MapPath $missionPath -Mods $mods
})


# ==============================================================================
# Run Form (Event Loop Entry)
# ==============================================================================

$Form.Add_Shown({
    $Form.Activate()
    Sync-ModList
})
[void] $Form.ShowDialog()
