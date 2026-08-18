# DayZ Local Server Mod Manager

A graphical mod management tool designed for DayZ dedicated servers (local/singleplayer). It simplifies mod loading, ordering, and types configuration, eliminating the tedious manual editing of `.bat` and `.xml` files.

---

<img width="500" alt="Screenshot 2026-08-18 232735" src="https://github.com/user-attachments/assets/64869db7-979b-46d2-8d0a-bd5fc727682d" />
<img width="500" alt="Screenshot 2026-08-18 232831" src="https://github.com/user-attachments/assets/d2f2d979-87b9-4032-b0c8-bd4f93392b39" />

---

## ✨ Features

- **Automatic scanning** – Scans your `!Workshop` folder for all mod folders starting with `@`.
- **Visual toggling** – Check a mod to load it, uncheck to unload; changes are reflected in your server batch file’s `modList` parameter instantly.
- **Custom ordering** – Drag-free reordering via buttons or keyboard shortcuts; the order is saved to `mod_order.json` and preserved across restarts.
- **Intelligent Junction management** – Creates or removes directory junctions (symbolic links) in the server root pointing to mod sources – no file copying, safe updates, and no accidental deletion of source folders.
- **Map‑specific types configuration**:
  - Supports multiple maps (automatically detects valid mission folders under `mpmissions`).
  - Scans mods for `type`‑related XML files, copies them to the map’s `db/ModTypes` directory.
  - Automatically updates the map’s `cfgeconomycore.xml` to include the types files.
  - Cleans up invalid configurations when mods are removed or renamed.
- **One‑click launch** – After all configurations are ready, click “Start Game” to save settings, update junctions, and launch the server (and the game via Steam).
- **Real‑time logging** – All operations are logged with color‑coded messages for easy troubleshooting.

---

## ⚠️ Before You Start (Mandatory Configuration)

### 1. Set up the configuration file

The tool now uses a **`settings.json`** file located in the `DayZ-LocalServer-ModManager-Data` folder (created automatically next to the script).  
On first run, it will try to guess the paths. If the guesses are incorrect, **you must edit this file manually** with a text editor:

```json
{
  "WorkshopPath": "D:\\SteamLibrary\\steamapps\\common\\DayZ\\!Workshop",
  "ServerPath": "D:\\SteamLibrary\\steamapps\\common\\DayZServer",
  "BatFileName": "LocalServer.bat"
}
```

- **`WorkshopPath`** – the full path to your DayZ workshop mod folder (contains all `@*` mods).
- **`ServerPath`** – the full path to your DayZ server root directory.
- **`BatFileName`** – the name of your batch file (e.g., `LocalServer.bat`). The tool will look for it inside `ServerPath`.

> **Note:** If you change these values, restart the tool.

### 2. Disable signature verification

In your `DayZServer` folder, open `serverDZ.cfg` with a text editor and ensure the following line exists (add it if missing):

```
verifySignatures = 0;
```

If this is set to `2` or missing, loading unsigned mods will fail and you will not be able to join the game.

---

## 🚀 Requirements

- **OS**: Windows 10 / 11 (64‑bit)
- **PowerShell**: Version 5.1 or later (built‑in)
- **.NET Framework**: 4.5+ (built‑in)
- **Permissions**: It is **strongly recommended** to run the script **as Administrator** to avoid permission errors when creating junctions.

---

## 🖱️ How to Use

### Launch the Tool

Right‑click `DayZModManager.ps1` → **Run with PowerShell**.

### Mod Manager Tab (Main Interface)

- **Mod list** – Shows all mods found in `!Workshop`. Checked mods will be loaded on launch.
- **Reordering**:
  - Select a mod, then click **Move Up** / **Move Dn** to adjust its position.
  - Keyboard shortcuts: **`Ctrl+↑`** / **`Ctrl+↓`** to move the selected mod up/down **within its checked/unchecked group** (checked items always stay above unchecked ones).
- **Select / Deselect All** – Click once to toggle all mods.
- **Start Game**:
  - Saves the current order to `mod_order.json`.
  - Updates the `modList` line in your batch file.
  - Creates or removes junctions in the server root for each mod.
  - Verifies that all mods with types configuration are also checked; if any are missing, it warns you and **prevents launch**.
  - If everything is correct, it executes the batch file to start the server and the game via Steam, then automatically closes the tool after 3 minutes to free resources.

### Map Config Tab (Types Management)

This page lets you manage `types` XML files for different maps – essential for custom items to spawn correctly.

- **Current Map** – Select a map from the dropdown (discovered from `mpmissions` and previously saved configs). Click **Apply** to switch. This will update the `template` in `serverDZ.cfg` and switch the save profile folder (`map_profiles`).
- **Mod dropdown** – Lists all mods from the main list. Select one and click **Config XML**.
- **Config XML**:
  - Automatically scans the chosen mod for any `.xml` files whose names contain `type`.
  - A dialog appears allowing you to check which files to include (all are selected by default).
  - Once confirmed, these files are copied to the current map’s `db/ModTypes` folder (created if needed), and `cfgeconomycore.xml` is updated to reference them.
  - The configured mods and their files appear in the table below.
- **Remove Selected** – Select one or more rows in the table and click this button to delete the associated types files and remove them from the configuration.
- **Clean Invalid** – Automatically removes entries for mods that no longer exist in the main list (deleted or renamed mods) and deletes their copied types files.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+↑` | Move selected mod up one position (within the same check group) |
| `Ctrl+↓` | Move selected mod down one position (within the same check group) |
| `↑` / `↓` | Navigate the list without changing order (selection only) |
| (Auto) | Checking/unchecking a mod automatically re‑groups the list (checked mods first) |

---

## 📁 Generated Files

- **`mod_order.json`** – Stores the display order of all mods (array of mod folder names). Saved in the data folder.
- **`types_config.json`** – Stores types configuration per map, including mod names and copied file paths. Saved in the data folder.
- **`map_profiles/`** – A folder under the server root that holds save data for different maps. The tool automatically switches this profile when you change the map.

---

## ⚠️ Important Notes

- The tool **only** creates or removes directory junctions – it never copies mod files into the server folder. Deleting a junction does **not** affect the original mod files in `!Workshop`.
- If a physical folder with the same name as a mod already exists in the server root, the tool will **skip** junction creation and log a warning – you must handle this manually.
- When switching maps, ensure the target mission folder contains a valid `cfgeconomycore.xml`; otherwise, the switch will fail.
- The “Start Game” button rewrites the `modList` line in your batch file but leaves all other content untouched. Avoid editing that line manually.
- If you have many mods, the initial scan may take a few seconds – please be patient.

---

## 🐛 Troubleshooting

**Q: I get a security warning or cannot run the script.**  
A: Right‑click the script → Properties → check “Unblock”, or run PowerShell as Administrator and execute:  
`Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`.

**Q: The tool reports “Workshop directory not found” or “Server path not found”.**  
A: Check the paths in `settings.json` (located in `DayZ-LocalServer-ModManager-Data`). They must be absolute and point to the correct folders.

**Q: After clicking “Start Game”, the server does not start.**  
A: Test your batch file manually (double‑click it). If it requires additional parameters, ensure they are correctly set in the file – the tool only modifies the `modList` line.

**Q: Custom items do not spawn in game even after types configuration.**  
A: Verify that `verifySignatures = 0;` is set in `serverDZ.cfg`. Also check the log output to confirm that files were copied and `cfgeconomycore.xml` was updated successfully.

**Q: My save data disappears after switching maps.**  
A: The tool automatically switches the `map_profiles` subdirectory, but only if your batch file contains a `set "serverProfile=..."` line. If missing, add it manually – otherwise the profile won’t change.

---

## 📜 License

This tool is distributed under the [MIT License](LICENSE). Feel free to use, modify, and share, but please retain the original author credits.

---

## 🤝 Contributing

If you have suggestions or find a bug, please open an Issue or submit a Pull Request.

---

**Enjoy a customised DayZ survival experience!** 🧟‍♂️🔫
