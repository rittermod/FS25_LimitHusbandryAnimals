# Limit Husbandry Animals

Limit the maximum number of animals in husbandry pens, pastures, and buildings. Set custom limits through an easy-to-use dialog.

Multiplayer support with permission system - admins can modify any pen, farm managers can modify their farm's pens.

## Features

- **Easy Limit Dialog:** Press L at any animal trigger to open the limit setter
- **Direct Input:** Type your desired limit - bounds shown, validation automatic
- **Custom Limits:** Set maximum animal counts per pen/building/pasture
- **Validation:** Cannot exceed original capacity or go below current animals
- **Savegame Persistence:** Limits saved per-savegame
- **Multiplayer Support:** Server validation, client sync, permission system
- **Console Commands:** lhaList, lhaSet, lhaReset for advanced users

## Installation

### From GitHub Releases
1. Download the latest release from [Releases](https://github.com/rittermod/FS25_LimitHusbandryAnimals/releases)
2. Place the `.zip` file in your mods folder:
   - **Windows**: `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\`
   - **macOS**: `~/Library/Application Support/FarmingSimulator2025/mods/`
3. Enable the mod in-game

## Usage

1. Walk to any animal loading trigger (pen, pasture, building)
2. Press **L** to open the limit dialog
3. Enter your desired limit (min/max bounds shown)
4. Press OK to apply, Cancel to discard

### Advanced: Console Commands

For changes without the dialog:

| Command | Description | Example |
|---------|-------------|---------|
| `lhaList` | Show all husbandries with their limits | `lhaList` |
| `lhaSet <index> <limit>` | Set a custom limit | `lhaSet 1 20` |
| `lhaReset <index>` | Reset to original capacity | `lhaReset 1` |

## Multiplayer Permissions

| Role | Permission |
|------|------------|
| **Admins** | Can modify any husbandry on any farm* |
| **Farm Managers** | Can modify husbandries owned by their farm |
| **Standard Players** | View only (no modification) |

*Game restricts trigger visibility by farm - use console commands to modify other farms' husbandries.


## Changelog

### 1.0.0.0
- First stable release
- Fixed activatable patching not registering basegame ACTIVATE_OBJECT action, which prevented opening the animal dialog

### 0.2.2.0
- Fixed compatibility with MoveHusbandryAnimals mod (both keybindings now work together)

See [CHANGELOG.md](CHANGELOG.md) for full version history.


## Credits

- **Author**: [Ritter](https://github.com/rittermod)

## Support

Found a bug or have a feature request? [Open an issue](https://github.com/rittermod/FS25_LimitHusbandryAnimals/issues)
