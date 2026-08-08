# DayZ-LocalServer-ModManager

一款专为 DayZ 独立服务器（本地单机）设计的图形化模组管理工具，帮你轻松管理模组加载、排序、types 配置，告别手动编辑 bat 和 xml 的繁琐过程。

---

<img width="500" alt="Screenshot 2026-08-08 221916" src="https://github.com/user-attachments/assets/ec2a3404-4456-4635-b1ef-1f25c8f1939e" />

<img width="500" alt="Screenshot 2026-08-08 221929" src="https://github.com/user-attachments/assets/a904e776-4a61-4148-8a81-8559cf7aa205" />

---

##  功能特性

-  **自动扫描**：读取 `!Workshop` 目录下所有以 `@` 开头的模组文件夹，无遗漏。
-  **可视化勾选**：勾选即加载，取消即卸载，状态自动反映到 `LocalServer.bat` 的 `modList` 参数。
-  **自定义排序**：快捷键调整模组顺序，并保存到 `mod_order.json`，下次启动保持顺序。
-  **智能 Junction 管理**：在服务器根目录自动创建/删除指向模组源的目录链接（Junction），避免复制大文件，且只操作链接，不损坏实体文件夹且同步模组更新。
-  **地图 Types 配置**：
  - 支持多地图（自动扫描 `mpmissions` 下的有效 mission 文件夹）。
  - 一键从模组中扫描 `type` 相关 XML 文件，复制到地图的 `db/ModTypes` 目录。
  - 自动更新地图的 `cfgeconomycore.xml`，引入 Types 文件。
  - 清理失效配置，移除已删除模组的 types 文件。
-  **一键启动**：完成所有配置后，点击“开始游戏”自动保存、更新配置，并启动 `DayZServer` 和游戏客户端（通过 Steam）。
-  **实时日志**：所有操作均有颜色区分日志输出，方便追踪错误。

---

## ⚠️ 使用前必读（必须配置！）

### 1. 编辑脚本中的三个变量

用记事本或任何文本编辑器打开 `DayZ-LocalServer-ModManager.ps1`，在文件开头找到以下三行：

```powershell
$WorkshopPath  = "<你的DayZ工坊模组目录>"   # 例如: D:\SteamLibrary\steamapps\common\DayZ\!Workshop
$ServerPath    = "<你的DayZ服务器根目录>"   # 例如: D:\SteamLibrary\steamapps\common\DayZServer
$BatFileName   = "<你的batch文件名>"        # 例如: LocalServer.bat
```

请根据你的实际安装路径修改，**三者缺一不可**，否则程序无法正常工作。

### 2. 关闭签名验证（必须操作！）

在 `DayZServer` 目录下找到 `serverDZ.cfg`，用记事本打开，确保存在以下设置（若没有则添加）：

```
verifySignatures = 0;
```

> 若该值为 `2` 或未设置，加载未签名的模组会失败，导致无法进入游戏。

---

## 🚀 运行环境

- **操作系统**：Windows 10 / 11（64位）
- **PowerShell**：版本 5.1 或更高（系统自带）
- **.NET Framework**：4.5+（系统自带）
- **权限**：建议以 **管理员身份** 运行脚本，避免创建 Junction 链接时因权限不足而失败。

---

## 🖱️ 使用方法

### 启动程序
右键点击 `DayZ-LocalServer-ModManager.ps1` → **使用 PowerShell 运行**。

### 模组管理页（主界面）

- **模组列表**：显示所有扫描到的模组，已勾选的表示将在启动时加载。
- **排序与调整**：
  - 点击 `▲ 上移` / `▼ 下移` 调整选中模组的位置。
  - 快捷键：**`Ctrl+↑`** / **`Ctrl+↓`** 快速上下移动当前选中的模组（**仅在同组内移动**，即已勾选和未勾选之间不会跨组，保证勾选组始终在前）。
- **全选/全不选**：点击 `全选` 按钮切换所有模组的勾选状态。
- **开始游戏**：
  - 自动保存当前排序到 `mod_order.json`。
  - 更新 `LocalServer.bat` 中的 `modList` 参数。
  - 在服务器根目录创建或删除对应模组的 Junction 链接。
  - 检查 Types 配置是否有遗漏勾选（如有则会提示并阻止启动）。
  - 若无问题，则执行 `LocalServer.bat` 启动服务器和游戏，并自动在 3 分钟后关闭本工具（避免占用内存）。

### 地图配置页（Types 管理）

此页面用于管理不同地图的 `types` 文件配置，让模组中的自定义物品能正常生成。

- **当前地图**：下拉框选择地图（自动从 `mpmissions` 目录和已保存配置中读取）。选择后需点击 `确定更改` 才会生效，同时会自动更新 `serverDZ.cfg` 中的 `template` 和切换对应的存档目录（`map_profiles`）。
- **模组下拉框**：显示主列表中所有模组，选择后点击 `配置 XML`。
- **配置 XML**：
  - 自动扫描所选模组中所有文件名包含 `type` 的 `.xml` 文件。
  - 弹出窗口供您勾选需要的文件（默认全选）。
  - 确认后，这些文件将被复制到当前地图的 `db/ModTypes` 目录下（自动创建），并更新 `cfgeconomycore.xml` 引用它们。
  - 结果会显示在下方的表格中。
- **移除选中**：在表格中选择一行或多行，点击后删除对应的 types 文件并更新配置。
- **清理失效**：自动检测当前地图配置中哪些模组已不在主列表中（即已被移除或重命名），并删除其对应的 types 文件和配置项。

---

## ⌨️ 快捷键一览

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+↑` | 将当前选中的模组向上移动一位（仅在同组内） |
| `Ctrl+↓` | 将当前选中的模组向下移动一位（仅在同组内） |
| 上下方向键 | 在列表中移动光标（选中项）但不改变顺序 |
| (无) | 勾选/取消勾选时自动重新排序（已勾选组在前） |

---

## 📁 生成的文件说明

- `mod_order.json` – 保存在服务器根目录，记录模组显示顺序（按顺序排列的模组名数组）。
- `types_config.json` – 保存在服务器根目录，记录每个地图的 types 配置（包含模组名及已复制的文件相对路径）。
- `map_profiles/` – 目录，用于存放不同地图的存档数据，切换地图时会自动切换该目录。

---

## ⚠️ 注意事项

- 本工具仅操作 **Junction 链接**，**不会**复制模组实体文件到服务器目录，因此删除 Junction 时不会影响 `!Workshop` 中的源文件。
- 如果服务器根目录下存在与模组同名的 **实体文件夹**，程序会跳过 Junction 创建并给出警告（请手动处理）。
- 修改地图时，请确保目标地图目录下存在 `cfgeconomycore.xml`，否则切换会失败。
- 每次点击“开始游戏”都会重写 `LocalServer.bat` 中的 `modList` 行，但不会修改其他内容（如启动参数、路径等），请勿手动编辑该行，以免被覆盖。
- 如果你有大量模组，初次启动扫描可能需要几秒钟，请耐心等待。

---

## 🐛 常见问题

### Q: 运行脚本时出现安全警告或无法执行？
A: 右键脚本 → 属性 → 勾选“解除锁定”；或以管理员身份打开 PowerShell 执行 `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`。

### Q: 提示“工坊目录未找到”或“服务器根目录未找到”？
A: 检查脚本开头的 `$WorkshopPath` 和 `$ServerPath` 是否配置正确，路径必须为绝对路径。

### Q: 点击“开始游戏”后服务器无反应？
A: 确认 `LocalServer.bat` 本身能否独立运行（双击运行）。若 Bat 需要额外参数，请确保其内容已正确配置，本工具只修改 `modList` 行。

### Q: Types 配置后，游戏内仍不生成自定义物品？
A: 确保 `serverDZ.cfg` 中 `verifySignatures = 0`；同时检查 `cfgeconomycore.xml` 中是否正确插入了 `<ce>` 块，可查阅日志确认复制和更新是否成功。

### Q: 切换地图后存档丢失？
A: 本工具会自动切换 `map_profiles` 子目录，但前提是 `LocalServer.bat` 中存在 `set serverProfile=...` 行。若你的 bat 未设置，请手动添加，否则存档路径不会切换。

---

## 📜 许可证

本工具遵循 [MIT License](LICENSE)。欢迎自由使用、修改和分发，但请保留原作者信息。

---

## 🤝 贡献

如果你有改进建议或发现 Bug，欢迎提交 Issue 或 Pull Request。

---

**祝你在 DayZ 的生存之旅中畅享自定义模组的乐趣！** 🧟‍♂️🔫
