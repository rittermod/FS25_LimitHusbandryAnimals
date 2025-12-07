# Limit Husbandry Animals [ALPHA]

Limit the maximum number of animals in husbandry pens, pastures, and buildings. Useful for keeping your farm manageable or creating gameplay challenges with restricted animal capacity.

Full multiplayer support with permission system - admins can modify any pen, farm managers can modify their farm's pens.

> **ALPHA RELEASE** - Core functionality complete. Limit changes via console commands only. GUI dialog coming in future update.

## Features

- **Custom Limits:** Set maximum animal counts per pen/building/pasture
- **Validation:** Cannot exceed original capacity or go below current animals
- **Savegame Persistence:** Limits saved per-savegame
- **Multiplayer Support:** Server validation, client sync, permission system
- **Console Commands:** lhaList, lhaSet, lhaReset for limit management

## Installation

### From GitHub Releases
1. Download the latest release from [Releases](https://github.com/rittermod/FS25_LimitHusbandryAnimals/releases)
2. Place the `.zip` file in your mods folder:
   - **Windows**: `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\`
   - **macOS**: `~/Library/Application Support/FarmingSimulator2025/mods/`
3. Enable the mod in-game

## Usage

1. Walk to any animal loading trigger (pen, pasture, building)
2. Press **L** to view current limits (current animals, current limit, original capacity)
3. Use console commands to change limits:

### Console Commands

| Command | Description | Example |
|---------|-------------|---------|
| `lhaList` | Show all husbandries with their limits | `lhaList` |
| `lhaSet <index> <limit>` | Set a custom limit | `lhaSet 1 20` |
| `lhaReset <index>` | Reset to original capacity | `lhaReset 1` |

## Multiplayer Permissions

| Role | Permission |
|------|------------|
| **Admins** | Can modify any husbandry on any farm |
| **Farm Managers** | Can modify husbandries owned by their farm |
| **Standard Players** | View only (no modification) |


## Changelog

### 0.1.0.0
- First functional release
- Added console commands for limit management (lhaList, lhaSet, lhaReset)
- Added keybind (L) to view pen info at animal triggers
- Added savegame persistence for custom limits
- Added full multiplayer support with server validation
- Added permission system (admins and farm managers)

### 0.0.0.1
- Initial alpha


## Credits

- **Author**: [Ritter](https://github.com/rittermod)

## Support

Found a bug or have a feature request? [Open an issue](https://github.com/rittermod/FS25_LimitHusbandryAnimals/issues)
