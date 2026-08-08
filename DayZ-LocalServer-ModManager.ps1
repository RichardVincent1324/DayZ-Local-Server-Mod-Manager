<#
===============================================================================
 DayZ 本地服模组可视化管理器
 版本: 1.2 (代码做减法 最终优化版)
 依赖: Windows 11 自带 PowerShell 5.1 + System.Windows.Forms
 用法: 右键本文件 → "使用 PowerShell 运行"
===============================================================================
#>

# ==============================================================================
# 第 1 步：路径配置（如需修改，只改下面两个路径即可）
# ==============================================================================


# [必改] 工坊模组下载目录（!Workshop 文件夹的绝对路径）
$WorkshopPath  = "<你的DayZ工坊模组目录>"   # 例如: D:\SteamLibrary\steamapps\common\DayZ\!Workshop
# [必改] DayZ 服务器根目录（DayZServer 文件夹的绝对路径）
$ServerPath    = "<你的DayZ服务器根目录>"   # 例如: D:\SteamLibrary\steamapps\common\DayZServer

# [必改] 你的启动批处理文件名（必须与 ServerPath 下的文件名完全一致）
$BatFileName   = "<你的batch文件名>"   # 例如: LocalServer.bat 请根据实际情况修改


# ------------------- 以下保持默认即可，无需改动 -------------------
# 模组顺序存储数据
$OrderFileName = "mod_order.json"
$BatFilePath   = Join-Path $ServerPath $BatFileName
$OrderFilePath = Join-Path $ServerPath $OrderFileName

# Types 配置存储 & 默认地图（若地图不存在，程序会自动扫描 mpmissions 目录）
$TypesConfigPath  = Join-Path $ServerPath "types_config.json"
$DefaultMissionPath = Join-Path $ServerPath "mpmissions\dayzOffline.chernarusplus"


# ==============================================================================
# 加载 WinForms 程序集
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ==============================================================================
# 创建主表单
# ==============================================================================

$Form = New-Object System.Windows.Forms.Form
$Form.Text           = "DayZ 本地服模组管理器"
$Form.Size           = New-Object System.Drawing.Size(800, 620)
$Form.MinimumSize    = New-Object System.Drawing.Size(600, 400)
$Form.StartPosition  = "CenterScreen"
$Form.Font           = New-Object System.Drawing.Font("Segoe UI", 9)
$Form.KeyPreview     = $true

# ==============================================================================
# 全局变量
# ==============================================================================

# 存储当前列表中所有模组名（按显示顺序），供上下移动时快速操作
$Script:ModNameList = @()

# 日志 RichTextBox 引用（GUI 创建后赋值）
$Script:LogBox = $null

# 用于抑制 ItemCheck 事件中自动排序的标记（批量操作时设为 $true）
$Script:SuppressItemCheckReSort = $false

# Types 配置页当前选择的地图路径
$Script:CurrentMissionPath = $DefaultMissionPath

# 地图下拉框显示名 → 完整路径的索引
$Script:MapDropdownIndex = @{}

# ==============================================================================
# 第 2 步：核心工具函数
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
    扫描 !Workshop 目录，返回所有以 @ 开头的文件夹名（不含路径）。
    #>
    if (-not (Test-Path -LiteralPath $WorkshopPath -PathType Container)) {
        Add-Log -Message "工坊目录未找到: $WorkshopPath" -Color "Red"
        return @()
    }
    $mods = Get-ChildItem -LiteralPath $WorkshopPath -Directory | Where-Object { $_.Name -like '@*' } | ForEach-Object { $_.Name }
    return @($mods)
}

function Read-ModOrder {
    <#
    .SYNOPSIS
    从 mod_order.json 中读取自定义模组排序。不存在或损坏时返回空数组。
    #>
    if (-not (Test-Path -LiteralPath $OrderFilePath -PathType Leaf)) {
        return @()
    }
    try {
        $json = Get-Content -LiteralPath $OrderFilePath -Raw | ConvertFrom-Json
        return @($json)
    } catch {
        Add-Log -Message "mod_order.json 格式损坏，已忽略自定义排序" -Color "DarkOrange"
        return @()
    }
}

function Write-ModOrder {
    <#
    .SYNOPSIS
    将当前模组名数组写入 mod_order.json。
    #>
    param([string[]]$ModNames)
    $json = ConvertTo-Json -InputObject @($ModNames) -Depth 1
    Set-Content -LiteralPath $OrderFilePath -Value $json -Encoding UTF8
}

# ==============================================================================
# Types 配置工具函数
# ==============================================================================

function Read-TypesConfig {
    <#
    .SYNOPSIS
    从 types_config.json 读取 Types 配置。不存在时返回默认结构。
    自动迁移旧格式 { mapPath, mods } → { maps, currentMap }。
    #>
    if (-not (Test-Path -LiteralPath $TypesConfigPath -PathType Leaf)) {
        $config = [PSCustomObject]@{ maps = [PSCustomObject]@{}; currentMap = $DefaultMissionPath }
        $config.maps | Add-Member -NotePropertyName $DefaultMissionPath -NotePropertyValue @()
        return $config
    }
    try {
        $config = Get-Content -LiteralPath $TypesConfigPath -Raw | ConvertFrom-Json

        # 迁移旧格式: { mapPath, mods } → { maps: { mapPath: mods }, currentMap: mapPath }
        if (-not ($config.PSObject.Properties.Name -contains 'maps')) {
            $oldMapPath = $config.mapPath
            $oldMods = if ($config.mods) { @($config.mods) } else { @() }
            $maps = [PSCustomObject]@{}
            $maps | Add-Member -NotePropertyName $oldMapPath -NotePropertyValue $oldMods
            $config = [PSCustomObject]@{ maps = $maps; currentMap = $oldMapPath }
            Write-TypesConfigFile $config
            Add-Log -Message "types_config.json 已自动迁移为新格式" -Color "LightGray"
        }
        return $config
    } catch {
        Add-Log -Message "types_config.json 格式损坏，使用默认配置" -Color "DarkOrange"
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
        Add-Log -Message "未找到 serverDZ.cfg，跳过 template 更新" -Color "DarkOrange"
        return
    }
    $content = Get-Content -LiteralPath $cfgPath -Raw
    if ($content -match 'template\s*=\s*"[^"]*"') {
        $content = $content -replace 'template\s*=\s*"[^"]*"', "template=`"$MissionFolderName`""
        Set-Content -LiteralPath $cfgPath -Value $content -Encoding UTF8 -NoNewline
        Add-Log -Message "serverDZ.cfg template 已更新为: $MissionFolderName" -Color "Gray"
    } else {
        Add-Log -Message "serverDZ.cfg 中未找到 template= 行，跳过更新" -Color "DarkOrange"
    }
}

function Update-ServerProfile {
    param([string]$MissionFolderName)
    $mapId = if ($MissionFolderName -match '\.([^.]+)$') { $matches[1] } else { $MissionFolderName }
    $profilesDir = Join-Path $ServerPath "map_profiles"
    $mapProfilePath = Join-Path $profilesDir $mapId

    if (-not (Test-Path -LiteralPath $mapProfilePath -PathType Container)) {
        New-Item -ItemType Directory -Path $mapProfilePath -Force | Out-Null
        Add-Log -Message "已创建存档目录: map_profiles\$mapId" -Color "Green"
    }

    $batContent = Get-Content -LiteralPath $BatFilePath -Raw
    $relativeProfile = "map_profiles\$mapId"
    if ($batContent -match '(?m)^\s*set\s+serverProfile\s*=\s*.*') {
        $batContent = $batContent -replace '(?m)^\s*set\s+serverProfile\s*=\s*.*', "set serverProfile=$relativeProfile"
        Set-Content -LiteralPath $BatFilePath -Value $batContent -Encoding ASCII -NoNewline
        Add-Log -Message "存档路径已切换: $relativeProfile" -Color "Green"
    } else {
        Add-Log -Message "LocalServer.bat 中未找到 set serverProfile= 行，跳过更新" -Color "DarkOrange"
    }
}

function Populate-MapDropdown {
    $config = Read-TypesConfig
    $Script:TypesMapDropdown.Items.Clear()
    $Script:MapDropdownIndex.Clear()

    # 来源 1: types_config.json 中已配置过的地图
    foreach ($mapKey in $config.maps.PSObject.Properties.Name) {
        $display = Split-Path $mapKey -Leaf
        if (-not $Script:MapDropdownIndex.ContainsKey($display)) {
            $Script:MapDropdownIndex[$display] = $mapKey
            [void]$Script:TypesMapDropdown.Items.Add($display)
        }
    }

    # 来源 2: mpmissions 目录下含 cfgeconomycore.xml 的子目录
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

    # 选中当前地图
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
    递归扫描指定模组目录，返回所有文件名含 "type"（不区分大小写）的 .xml 文件完整路径。
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
    弹出模态窗口，让用户从扫描到的 XML 文件列表中勾选需要的文件。
    返回被选中的完整路径数组。
    #>
    param(
        [string]$ModName,
        [string[]]$FoundFiles
    )
    if ($FoundFiles.Count -eq 0) {
        $null = [System.Windows.Forms.MessageBox]::Show("未在模组 $ModName 中找到含 'type' 关键字的 XML 文件。", "提示", "OK", "Information")
        return @()
    }

    $pickerForm = New-Object System.Windows.Forms.Form
    $pickerForm.Text = "选择 types 文件 - $ModName"
    $pickerForm.Size = New-Object System.Drawing.Size(620, 400)
    $pickerForm.StartPosition = "CenterParent"
    $pickerForm.MinimumSize = New-Object System.Drawing.Size(400, 250)

    $pickerLabel = New-Object System.Windows.Forms.Label
    $pickerLabel.Text = "发现以下 types 文件，请勾选需要的:"
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
    $pickerBtnOk.Text = "确定"
    $pickerBtnOk.Size = New-Object System.Drawing.Size(80, 28)
    $pickerBtnOk.Anchor = "Bottom,Right"
    $pickerBtnOk.Location = New-Object System.Drawing.Point(430, 322)
    $pickerBtnOk.Add_Click({ $pickerForm.DialogResult = "OK"; $pickerForm.Close() })

    $pickerBtnCancel = New-Object System.Windows.Forms.Button
    $pickerBtnCancel.Text = "取消"
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
    更新地图 cfgeconomycore.xml，插入/更新 <ce folder="ModTypes"> 块来引用模组 types 文件。
    如果 ModTypeFileNames 为空，则删除 ModTypes 引用块。
    #>
    param(
        [string]$MissionPath,
        [string[]]$ModTypeFileNames
    )
    $cfgPath = Join-Path $MissionPath "cfgeconomycore.xml"
    if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) {
        Add-Log -Message "未找到 cfgeconomycore.xml: $cfgPath" -Color "Red"
        return $false
    }

    $content = Get-Content -LiteralPath $cfgPath -Raw

    # 移除已有的 ModTypes 引用块（兼容新旧格式）
    $content = $content -replace '(?s)\s*<ce\s+folder="\./db/ModTypes">.*?</ce>\s*', "`r`n"
    $content = $content -replace '(?s)\s*<ce\s+folder="db\\ModTypes">.*?</ce>\s*', "`r`n"
    $content = $content -replace '(?s)\s*<ce\s+folder="ModTypes">.*?</ce>\s*', "`r`n"

    # 构建新块
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
        Add-Log -Message "cfgeconomycore.xml 已更新" -Color "Gray"
        return $true
    } catch {
        Add-Log -Message "写入 cfgeconomycore.xml 失败: $($_.Exception.Message)" -Color "Red"
        return $false
    }
}

function Save-MapTypesConfig {
    <#
    .SYNOPSIS
    保存指定地图的模组 types 配置，更新 cfgeconomycore.xml 并刷新 UI。
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
    刷新 Types 配置页的 DataGridView 和下拉框。
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
    解析 LocalServer.bat 中的 set modList= 行，返回已加载的模组名数组。
    #>
    if (-not (Test-Path -LiteralPath $BatFilePath -PathType Leaf)) {
        Add-Log -Message "未找到 LocalServer.bat: $BatFilePath" -Color "Red"
        return @()
    }
    $content = Get-Content -LiteralPath $BatFilePath -Raw
    if ($content -match '(?m)^\s*set\s+modList\s*=\s*"(-mod=.*?)"') {
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
    更新 LocalServer.bat 中的 set modList= 行。其余内容完全不动。
    #>
    param([string[]]$ModNames)

    if (-not (Test-Path -LiteralPath $BatFilePath -PathType Leaf)) {
        Add-Log -Message "未找到 LocalServer.bat，无法写入" -Color "Red"
        return $false
    }

    $content = Get-Content -LiteralPath $BatFilePath -Raw

    $modString = ($ModNames -join ';')
    # 如果只有一个或多个模组，统一在末尾加分号
    if ($modString -ne '') {
        $modString += ';'
    }
    $newLine = 'set modList="-mod=' + $modString + '"'

    # 替换 set modList= 行
    if ($content -match '(?m)^\s*set\s+modList\s*=\s*".*?"') {
        $newContent = $content -replace '(?m)^\s*set\s+modList\s*=\s*".*?"', $newLine
        try {
            Set-Content -LiteralPath $BatFilePath -Value $newContent -Encoding ASCII -NoNewline
            Add-Log -Message "Bat 配置已保存，共加载 $($ModNames.Count) 个模组" -Color "Green"
            return $true
        } catch {
            Add-Log -Message "写入 Bat 文件失败: $($_.Exception.Message)" -Color "Red"
            return $false
        }
    } else {
        Add-Log -Message "在 LocalServer.bat 中未找到 set modList= 行，无法更新" -Color "Red"
        return $false
    }
}

function Test-IsJunction {
    <#
    .SYNOPSIS
    检测给定路径是否为 Junction（目录符号链接）。
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
    在 DayZServer 目录下为指定模组创建 Junction，目标指向 !Workshop 中的对应文件夹。
    返回 $true 表示创建成功，$false 表示失败或已跳过。
    #>
    param([string]$ModName)

    $junctionPath = Join-Path $ServerPath $ModName
    $targetPath   = Join-Path $WorkshopPath $ModName

    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        Add-Log -Message "目标模组不存在: $targetPath" -Color "Red"
        return $false
    }

    # 已存在
    if (Test-Path -LiteralPath $junctionPath) {
        if (Test-IsJunction $junctionPath) {
            return $true
        }
        # 是同名实体文件夹，跳过
        Add-Log -Message "☠ ${ModName}: 同名实体文件夹已存在，无法创建 Junction（请手动处理）" -Color "Red"
        return $false
    }

    try {
        New-Item -ItemType Junction -Path $junctionPath -Target $targetPath -Force -ErrorAction Stop | Out-Null
        Add-Log -Message "已创建 Junction: $ModName" -Color "Green"
        return $true
    } catch {
        Add-Log -Message "创建 Junction 失败 ($ModName): $($_.Exception.Message)" -Color "Red"
        return $false
    }
}

function Remove-ModJunction {
    <#
    .SYNOPSIS
    仅当路径是 Junction 时才删除。实体文件夹跳过不动。
    返回 $true 表示删除成功（或本身就不存在，无需删除），$false 表示出错。
    #>
    param([string]$ModName)

    $junctionPath = Join-Path $ServerPath $ModName

    if (-not (Test-Path -LiteralPath $junctionPath)) {
        return $true
    }

    if (-not (Test-IsJunction $junctionPath)) {
        Add-Log -Message "☠ ${ModName}: 是实体文件夹而非 Junction，已跳过删除" -Color "Red"
        return $false
    }

    try {
        # rmdir 删除 Junction 链接本身，不会影响目标文件夹
        cmd /c rmdir "`"$junctionPath`""
        if ($LASTEXITCODE -eq 0) {
            Add-Log -Message "已删除 Junction: $ModName" -Color "DarkOrange"
            return $true
        } else {
            Add-Log -Message "删除 Junction 失败 ($ModName): exit code $LASTEXITCODE" -Color "Red"
            return $false
        }
    } catch {
        Add-Log -Message "删除 Junction 失败 ($ModName): $($_.Exception.Message)" -Color "Red"
        return $false
    }
}

# ==============================================================================
# 第 4 步：列表填充与勾选同步
# ==============================================================================

function Sync-ModList {
    <#
    .SYNOPSIS
    扫描 !Workshop，结合 mod_order.json 排序，
    填充 CheckedListBox，并根据 LocalServer.bat 勾选对应项。
    #>

    # 1. 获取工坊中所有 @ 模组
    $workshopMods = Get-WorkshopMods
    Add-Log -Message "已扫描到 $($workshopMods.Count) 个模组" -Color "LightGray"

    if ($workshopMods.Count -eq 0) {
        $Script:ModListBox.Items.Clear()
        $Script:ModNameList = @()
        Add-Log -Message "工坊中没有检测到任何模组" -Color "DarkOrange"
        return
    }

    # 2. 读取自定义排序
    $orderMods = Read-ModOrder

    # 3. 合并排序：先放入 order 中已知的（保持 json 顺序），再追加新模组
    $sorted = New-Object 'System.Collections.Generic.List[string]'
    $workshopSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in $workshopMods) { [void]$workshopSet.Add($m) }

    # 遍历自定义排序，保留仍存在于工坊中的模组
    foreach ($m in $orderMods) {
        if ($workshopSet.Contains($m)) {
            [void]$sorted.Add($m)
            [void] $workshopSet.Remove($m)
        }
    }

    # 追加工坊中新增的模组（按名字排序，保证可预测性）
    $remaining = $workshopSet | Sort-Object
    foreach ($m in $remaining) {
        [void]$sorted.Add($m)
    }

    $Script:ModNameList = @($sorted)

    # 4. 读取 Bat 中已加载的模组
    $batMods = Read-BatModList

    # 5. 填充 CheckedListBox
    $Script:ModListBox.BeginUpdate()
    $Script:ModListBox.Items.Clear()
    foreach ($modName in $sorted) {
        [void] $Script:ModListBox.Items.Add($modName)
    }

    # 根据 Bat 配置勾选对应项
    $Script:SuppressItemCheckReSort = $true
    $batSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in [string[]]$batMods) { [void]$batSet.Add($m) }
    for ($i = 0; $i -lt $Script:ModListBox.Items.Count; $i++) {
        $Script:ModListBox.SetItemChecked($i, $batSet.Contains($Script:ModListBox.Items[$i].ToString()))
    }
    $Script:SuppressItemCheckReSort = $false
    $Script:ModListBox.EndUpdate()

    $checkedCount = $Script:ModListBox.CheckedItems.Count
    Add-Log -Message "已根据本地配置勾选 $checkedCount 个模组" -Color "LightGray"

    # 清理孤儿 Junction（模组源已从 !Workshop 删除）
    $cleanupSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($m in $Script:ModNameList) { [void]$cleanupSet.Add($m) }
    $serverItems = Get-ChildItem -LiteralPath $ServerPath -Directory | Where-Object { $_.Name -like '@*' }
    foreach ($item in $serverItems) {
        $modName = $item.Name
        if (-not $cleanupSet.Contains($modName) -and (Test-IsJunction $item.FullName)) {
            if (Remove-ModJunction $modName) {
                Add-Log -Message "已清理残留 Junction: $modName (源已删除)" -Color "DarkOrange"
            }
        }
    }
}

# ==============================================================================
# 第 3 步：搭建 GUI 布局
# ==============================================================================

# --- 主布局容器 (4行 × 2列) ---
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

# --- Row 0: 路径显示区 (跨两列) ---
$PathPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$PathPanel.Dock          = "Fill"
$PathPanel.FlowDirection = "TopDown"
$PathPanel.AutoSize      = $true

$LabelWorkshop = New-Object System.Windows.Forms.Label
$LabelWorkshop.Text      = "工坊模组源目录: $WorkshopPath"
$LabelWorkshop.AutoSize  = $true
$LabelWorkshop.ForeColor = "DarkSlateGray"

$LabelServer = New-Object System.Windows.Forms.Label
$LabelServer.Text      = "服务器根目录: $ServerPath"
$LabelServer.AutoSize  = $true
$LabelServer.ForeColor = "DarkSlateGray"

$PathPanel.Controls.Add($LabelWorkshop)
$PathPanel.Controls.Add($LabelServer)
$TableLayout.Controls.Add($PathPanel, 0, 0)
$TableLayout.SetColumnSpan($PathPanel, 2)

# --- Row 1 Col 0: 模组列表 (CheckedListBox) ---
$Script:ModListBox = New-Object System.Windows.Forms.CheckedListBox
$Script:ModListBox.Dock          = "Fill"
$Script:ModListBox.IntegralHeight = $false
$Script:ModListBox.ItemHeight    = 22
$Script:ModListBox.CheckOnClick  = $true
$TableLayout.Controls.Add($Script:ModListBox, 0, 1)

# --- Row 1 Col 1: 排序按钮 ---
$SortPanel = New-Object System.Windows.Forms.Panel
$SortPanel.Dock  = "Fill"
$SortPanel.Width = 80

$Script:BtnUp = New-Object System.Windows.Forms.Button
$Script:BtnUp.Text     = "▲ 上移"
$Script:BtnUp.Width    = 68
$Script:BtnUp.Height   = 30
$Script:BtnUp.Location = New-Object System.Drawing.Point(6, 0)

$Script:BtnDown = New-Object System.Windows.Forms.Button
$Script:BtnDown.Text     = "▼ 下移"
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

# --- Row 2: 操作按钮区 (跨两列) ---
$BtnPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$BtnPanel.Dock          = "Fill"
$BtnPanel.FlowDirection = "LeftToRight"
$BtnPanel.Padding       = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)

$Script:BtnRefresh = New-Object System.Windows.Forms.Button
$Script:BtnRefresh.Text   = "刷新列表"
$Script:BtnRefresh.Width  = 90
$Script:BtnRefresh.Height = 28

$Script:BtnSelectAll = New-Object System.Windows.Forms.Button
$Script:BtnSelectAll.Text   = "全选"
$Script:BtnSelectAll.Width  = 90
$Script:BtnSelectAll.Height = 28

$Script:BtnComplete = New-Object System.Windows.Forms.Button
$Script:BtnComplete.Text      = "开始游戏"
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

# --- Row 3: 日志区 (跨两列) ---
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
# 构建 TabControl（模组管理页 + Types 配置页）
# ==============================================================================

$TabControl = New-Object System.Windows.Forms.TabControl
$TabControl.Dock = "Fill"

# --- Tab 1: 模组管理页（现有布局全部放入）---
$ModTabPage = New-Object System.Windows.Forms.TabPage
$ModTabPage.Text = "模组管理"
$ModTabPage.Controls.Add($TableLayout)

# --- Tab 2: Types 配置页 ---
$Script:TypesPage = New-Object System.Windows.Forms.TabPage
$Script:TypesPage.Text = "地图配置"
$Script:TypesPage.Padding = New-Object System.Windows.Forms.Padding(10)

$TypesLayout = New-Object System.Windows.Forms.TableLayoutPanel
$TypesLayout.Dock = "Fill"
$TypesLayout.ColumnCount = 1
$TypesLayout.RowCount = 5
[void]$TypesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 36)))
[void]$TypesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 42)))
[void]$TypesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent", 100)))
[void]$TypesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 38)))
[void]$TypesLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 22)))

# Row 0: 地图选择栏
$TypesTopPanel = New-Object System.Windows.Forms.TableLayoutPanel
$TypesTopPanel.Dock = "Fill"
$TypesTopPanel.ColumnCount = 4
[void]$TypesTopPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 70)))
[void]$TypesTopPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 260)))
[void]$TypesTopPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 90)))
[void]$TypesTopPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))

$TypesMapCaption = New-Object System.Windows.Forms.Label
$TypesMapCaption.Text = "当前地图:"
$TypesMapCaption.AutoSize = $true
$TypesMapCaption.TextAlign = "MiddleLeft"

$Script:TypesMapDropdown = New-Object System.Windows.Forms.ComboBox
$Script:TypesMapDropdown.Dock = "Fill"
$Script:TypesMapDropdown.DropDownStyle = "DropDownList"
$Script:TypesMapDropdown.Height = 28

$Script:BtnConfirmMap = New-Object System.Windows.Forms.Button
$Script:BtnConfirmMap.Text = "确定更改"
$Script:BtnConfirmMap.Dock = "Fill"
$Script:BtnConfirmMap.Height = 28
$Script:BtnConfirmMap.Enabled = $false

$TypesTopPanel.Controls.Add($TypesMapCaption, 0, 0)
$TypesTopPanel.Controls.Add($Script:TypesMapDropdown, 1, 0)
$TypesTopPanel.Controls.Add($Script:BtnConfirmMap, 2, 0)
$TypesLayout.Controls.Add($TypesTopPanel, 0, 0)

# Row 1: 操作区（模组选择 + 配置 XML 按钮）
$TypesActionPanel = New-Object System.Windows.Forms.TableLayoutPanel
$TypesActionPanel.Dock = "Fill"
$TypesActionPanel.ColumnCount = 4
[void]$TypesActionPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 70)))
[void]$TypesActionPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 260)))
[void]$TypesActionPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 90)))
[void]$TypesActionPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))
$TypesActionPanel.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)

$TypesModCaption = New-Object System.Windows.Forms.Label
$TypesModCaption.Text = "模组:"
$TypesModCaption.Dock = "Fill"
$TypesModCaption.AutoSize = $false
$TypesModCaption.TextAlign = "MiddleLeft"

$Script:TypesModDropdown = New-Object System.Windows.Forms.ComboBox
$Script:TypesModDropdown.Dock = "Fill"
$Script:TypesModDropdown.DropDownStyle = "DropDownList"
$Script:TypesModDropdown.Height = 28

$Script:BtnConfigXml = New-Object System.Windows.Forms.Button
$Script:BtnConfigXml.Text = "配置 XML"
$Script:BtnConfigXml.Width = 90
$Script:BtnConfigXml.Height = 28

$TypesActionPanel.Controls.Add($TypesModCaption, 0, 0)
$TypesActionPanel.Controls.Add($Script:TypesModDropdown, 1, 0)
$TypesActionPanel.Controls.Add($Script:BtnConfigXml, 2, 0)
$TypesLayout.Controls.Add($TypesActionPanel, 0, 1)

# Row 2: DataGridView（已配置 types 的模组列表）
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
$colModName.HeaderText = "模组名"
$colModName.FillWeight = 50
[void]$Script:TypesDataGrid.Columns.Add($colModName)

$colFiles = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colFiles.HeaderText = "Types 文件"
$colFiles.FillWeight = 50
[void]$Script:TypesDataGrid.Columns.Add($colFiles)

$TypesLayout.Controls.Add($Script:TypesDataGrid, 0, 2)

# Row 3: 底部操作栏（移除选中 / 清理失效）
$TypesBottomPanel = New-Object System.Windows.Forms.TableLayoutPanel
$TypesBottomPanel.Dock = "Fill"
$TypesBottomPanel.ColumnCount = 3
[void]$TypesBottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 100)))
[void]$TypesBottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))
[void]$TypesBottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 100)))

$Script:BtnRemoveSelected = New-Object System.Windows.Forms.Button
$Script:BtnRemoveSelected.Text = "移除选中"
$Script:BtnRemoveSelected.Dock = "Fill"
$Script:BtnRemoveSelected.Height = 30

$Script:BtnClearInvalid = New-Object System.Windows.Forms.Button
$Script:BtnClearInvalid.Text = "清理失效"
$Script:BtnClearInvalid.Dock = "Fill"
$Script:BtnClearInvalid.Height = 30

$TypesBottomPanel.Controls.Add($Script:BtnRemoveSelected, 0, 0)
$TypesBottomPanel.Controls.Add($Script:BtnClearInvalid, 2, 0)
$TypesLayout.Controls.Add($TypesBottomPanel, 0, 3)

# Row 4: 提示文字
$TypesHintLabel = New-Object System.Windows.Forms.Label
$TypesHintLabel.Text = "注: 第三方地图 mission 文件夹需手动放入 mpmissions 目录；灰色条目表示对应模组已失效"
$TypesHintLabel.Dock = "Fill"
$TypesHintLabel.ForeColor = "DarkGray"
$TypesHintLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$TypesHintLabel.TextAlign = "MiddleLeft"
$TypesHintLabel.Padding = New-Object System.Windows.Forms.Padding(2, 0, 0, 0)
$TypesLayout.Controls.Add($TypesHintLabel, 0, 4)

$Script:TypesPage.Controls.Add($TypesLayout)

# --- 组装 TabControl 并挂载到表单 ---
[void]$TabControl.TabPages.Add($ModTabPage)
[void]$TabControl.TabPages.Add($Script:TypesPage)
$Form.Controls.Add($TabControl)

# 将日志控件引用绑定到全局变量，供 Add-Log 使用
$Script:LogBox = $LogBoxCtrl

# ==============================================================================
# 第 5 步：交互事件处理
# ==============================================================================

# 辅助：交换 CheckedListBox 中相邻两项（内部操作，保留勾选状态）
function Swap-CheckedItem {
    param([int]$Index, [int]$Offset)
    if ($Script:ModListBox.Items.Count -eq 0) { return }
    $otherIdx = $Index + $Offset
    if ($otherIdx -lt 0 -or $otherIdx -ge $Script:ModListBox.Items.Count) { return }

    # 禁止跨勾选状态组交换（已勾选 / 未勾选仅允许组内调整）
    if ($Script:ModListBox.GetItemChecked($Index) -ne $Script:ModListBox.GetItemChecked($otherIdx)) { return }

    # 交换显示列表
    $itemA      = $Script:ModListBox.Items[$Index]
    $itemB      = $Script:ModListBox.Items[$otherIdx]
    $checkedA   = $Script:ModListBox.GetItemChecked($Index)
    $checkedB   = $Script:ModListBox.GetItemChecked($otherIdx)

    $Script:ModListBox.Items[$Index]    = $itemB
    $Script:ModListBox.Items[$otherIdx] = $itemA
    $Script:ModListBox.SetItemChecked($Index, $checkedB)
    $Script:ModListBox.SetItemChecked($otherIdx, $checkedA)
    $Script:ModListBox.SelectedIndex = $otherIdx

    # 同步 ModNameList
    $temp = $Script:ModNameList[$Index]
    $Script:ModNameList[$Index]    = $Script:ModNameList[$otherIdx]
    $Script:ModNameList[$otherIdx] = $temp
}

# --- 刷新列表 ---
$Script:BtnRefresh.Add_Click({
    Sync-ModList
})

# --- 全选 / 全不选 ---
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

    $Script:BtnSelectAll.Text = if ($newState) { "全不选" } else { "全选" }
})

# --- 上移 ---
$Script:BtnUp.Add_Click({
    $idx = $Script:ModListBox.SelectedIndex
    if ($idx -le 0) { return }
    Swap-CheckedItem -Index $idx -Offset -1
})

# --- 下移 ---
$Script:BtnDown.Add_Click({
    $idx = $Script:ModListBox.SelectedIndex
    if ($idx -lt 0 -or $idx -ge $Script:ModListBox.Items.Count - 1) { return }
    Swap-CheckedItem -Index $idx -Offset 1
})

# --- 键盘快捷键 Ctrl+↑ / Ctrl+↓ ---
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

# --- 勾选时自动分组排序：已勾选的在前，未勾选的在后 ---
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
        $Script:BtnSelectAll.Text = if ($allChecked) { "全不选" } else { "全选" }
    })
    $timer.Start()
})

# ==============================================================================
# 第 6 步：[完成] 按钮 — 一次性提交全部操作
# ==============================================================================

$Script:BtnComplete.Add_Click({
    if ($Script:ModListBox.Items.Count -eq 0) {
        Add-Log -Message "列表为空，无需操作" -Color "DarkOrange"
        return
    }

    $Script:BtnComplete.Enabled = $false
    $Script:BtnComplete.Text    = "处理中..."

    $Form.Refresh()

    try {
        # --- 1. 收集当前状态 ---
        $allModsInOrder = @($Script:ModNameList)
        $checkedMods = New-Object 'System.Collections.Generic.List[string]'
        for ($i = 0; $i -lt $Script:ModListBox.Items.Count; $i++) {
            if ($Script:ModListBox.GetItemChecked($i)) {
                $checkedMods.Add($Script:ModListBox.Items[$i].ToString())
            }
        }

        Add-Log -Message "==================== 操作汇总 ====================" -Color "Cyan"

        # --- 2. 保存模组排序到 mod_order.json ---
        Write-ModOrder -ModNames $allModsInOrder

        # --- 3. 更新 LocalServer.bat ---
        Write-BatModList -ModNames $checkedMods

        # --- 4. 同步 Junction ---
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
                        Add-Log -Message "☠ ${modName}: 同名实体文件夹已存在，无法创建 Junction（请手动处理）" -Color "Red"
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

        # --- 5. Junction 校验：勾选但链接缺失 ---
        foreach ($modName in $checkedMods) {
            $junctionPath = Join-Path $ServerPath $modName
            if (-not (Test-IsJunction $junctionPath)) {
                Add-Log -Message "⚠ $modName 已勾选加载，但 Junction 链接不存在！" -Color "Red"
            }
        }

        # --- 6. 汇总 ---
        Add-Log -Message "Junction 创建: $createdCount / 删除: $deletedCount / 跳过: $skippedCount" -Color "LightGray"

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
            Add-Log -Message "Types 配置: 已配置types的模组 $configuredCount 个, 其中 $checkedConfigured 个已勾选" -Color "LightGray"
            if ($uncheckedConfigured.Count -gt 0) {
                $names = ($uncheckedConfigured -join ', ')
                Add-Log -Message "已配置types 但遗漏勾选的模组: $names" -Color "Red"
                $skipLaunch = $true
            }
        }
        Add-Log -Message "==================================================" -Color "Cyan"

        # --- 7. 启动服务器和游戏 ---
        if ($skipLaunch) {
            Add-Log -Message "检测到遗漏的 types 配置，已跳过启动" -Color "DarkOrange"
        } else {
            Start-Process -FilePath $BatFilePath -WorkingDirectory $ServerPath
            Add-Log -Message "Bat 已启动, DayZ 将通过 Steam 运行, 程序将在3分钟后关闭..." -Color "Cyan"

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
        Add-Log -Message "操作失败: $($_.Exception.Message)" -Color "Red"
    } finally {
        $Script:BtnComplete.Enabled = $true
        $Script:BtnComplete.Text    = "开始游戏"
    }
})

# ==============================================================================
# 第 7 步：Types 配置页事件处理
# ==============================================================================

$TabControl.Add_SelectedIndexChanged({
    if ($TabControl.SelectedTab -eq $Script:TypesPage) {
        Sync-TypesList
    }
})

# --- 地图配置页 ---

# --- 确定更改（下拉框确认） ---
$Script:BtnConfirmMap.Add_Click({
    $selected = $Script:TypesMapDropdown.SelectedItem
    if (-not $selected) {
        Add-Log -Message "请先在下拉框中选择一个地图" -Color "DarkOrange"
        return
    }
    $newPath = $Script:MapDropdownIndex[$selected.ToString()]
    $cfgPath = Join-Path $newPath "cfgeconomycore.xml"
    if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) {
        $null = [System.Windows.Forms.MessageBox]::Show("所选地图目录下未找到 cfgeconomycore.xml，请重新选择。", "路径无效", "OK", "Warning")
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
    Add-Log -Message "地图已切换: $($Script:CurrentMissionPath)" -Color "Green"
})

# --- 地图下拉框选择变更 ---
$Script:TypesMapDropdown.Add_SelectedIndexChanged({
    $selected = $Script:TypesMapDropdown.SelectedItem
    if ($selected) {
        $mapPath = $Script:MapDropdownIndex[$selected.ToString()]
        $Script:BtnConfirmMap.Enabled = ($mapPath -ne $Script:CurrentMissionPath)
    }
})

# --- 配置 XML ---
$Script:BtnConfigXml.Add_Click({
    $modName = $Script:TypesModDropdown.SelectedItem
    if (-not $modName) {
        Add-Log -Message "请先从下拉框中选择一个模组" -Color "DarkOrange"
        return
    }

    Add-Log -Message "正在扫描 $modName 中的 types 文件..." -Color "LightGray"
    $foundFiles = Find-ModTypeFiles -ModName $modName
    Add-Log -Message "找到 $($foundFiles.Count) 个候选文件" -Color "LightGray"

    $selectedFiles = Show-TypeFilePicker -ModName $modName -FoundFiles $foundFiles
    if ($selectedFiles.Count -eq 0) {
        Add-Log -Message "已取消配置" -Color "Gray"
        return
    }

    $missionPath = $Script:CurrentMissionPath
    $modTypesDir = Join-Path $missionPath "db\ModTypes"
    if (-not (Test-Path -LiteralPath $modTypesDir -PathType Container)) {
        New-Item -ItemType Directory -Path $modTypesDir -Force | Out-Null
    }

    $config = Read-TypesConfig
    $mods = Get-MapModsFromConfig $config $missionPath

    # 移除该模组的旧配置
    $oldEntry = $mods | Where-Object { $_.modName -eq $modName }
    if ($oldEntry) {
        foreach ($oldFile in $oldEntry.copiedFiles) {
            $oldPath = Join-Path $missionPath $oldFile
            if (Test-Path -LiteralPath $oldPath) {
                Remove-Item -LiteralPath $oldPath -Force
                Add-Log -Message "删除旧文件: $oldFile" -Color "Gray"
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
        Add-Log -Message "已复制: $destName" -Color "Green"
    }

    $newEntry = @{
        modName     = $modName
        copiedFiles = @($copiedFiles)
    }
    $mods += $newEntry
    Save-MapTypesConfig -MapPath $missionPath -Mods $mods
    Add-Log -Message "$modName 的 types 配置已完成" -Color "Green"
})

# --- 移除选中 ---
$Script:BtnRemoveSelected.Add_Click({
    $selectedRows = $Script:TypesDataGrid.SelectedRows
    if ($selectedRows.Count -eq 0) {
        Add-Log -Message "请先在表格中选中要移除的行" -Color "DarkOrange"
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
                Add-Log -Message "已删除: $leafName" -Color "DarkOrange"
            }
            $entry.copiedFiles = @($entry.copiedFiles | Where-Object { $_ -ne $matchFile })
        }
        if ($entry.copiedFiles.Count -eq 0) {
            $mods = @($mods | Where-Object { $_.modName -ne $modName })
            Add-Log -Message "已移除 $modName 的 types 配置 (无剩余文件)" -Color "DarkOrange"
        }
    }

    Save-MapTypesConfig -MapPath $missionPath -Mods $mods
})

# --- 清理失效 ---
$Script:BtnClearInvalid.Add_Click({
    $missionPath = $Script:CurrentMissionPath
    $config = Read-TypesConfig
    $mods = Get-MapModsFromConfig $config $missionPath
    if ($mods.Count -eq 0) {
        Add-Log -Message "当前没有 types 配置" -Color "DarkOrange"
        return
    }

    $invalidMods = @($mods | Where-Object { $Script:ModNameList -notcontains $_.modName })
    if ($invalidMods.Count -eq 0) {
        Add-Log -Message "没有失效的 types 配置" -Color "LightGray"
        return
    }

    foreach ($entry in $invalidMods) {
        foreach ($file in $entry.copiedFiles) {
            $filePath = Join-Path $missionPath $file
            if (Test-Path -LiteralPath $filePath) {
                Remove-Item -LiteralPath $filePath -Force
                Add-Log -Message "已删除: $(Split-Path $file -Leaf) (模组 $($entry.modName) 已失效)" -Color "DarkOrange"
            }
        }
        Add-Log -Message "已清理 $($entry.modName) 的 types 配置 (模组已失效)" -Color "DarkOrange"
    }
    $mods = @($mods | Where-Object { $Script:ModNameList -contains $_.modName })
    Save-MapTypesConfig -MapPath $missionPath -Mods $mods
})


# ==============================================================================
# 运行表单（事件循环入口）
# ==============================================================================

$Form.Add_Shown({
    $Form.Activate()
    Sync-ModList
})
[void] $Form.ShowDialog()
