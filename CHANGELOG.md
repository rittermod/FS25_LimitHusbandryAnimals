# Changelog

## 1.0.1.0
- Limits can now exceed default pen capacity, allowing more animals than the original maximum

## 1.0.0.0
- First stable release
- Fixed activatable patching not registering basegame ACTIVATE_OBJECT action, which prevented opening the animal dialog

## 0.2.2.0
- Fixed compatibility with MoveHusbandryAnimals mod (both keybindings now work together)

## 0.2.1.0
- Clarified multiplayer admin permissions (use console for cross-farm modifications)

## 0.2.0.0
- Added GUI dialog for setting limits (press L at animal trigger)
- Added direct number input with automatic validation
- Changed keybind behavior: L now opens dialog instead of showing info text
- Console commands remain available for advanced users

## 0.1.0.0
- First functional release
- Added console commands for limit management (lhaList, lhaSet, lhaReset)
- Added keybind (L) to view pen info at animal triggers
- Added savegame persistence for custom limits
- Added full multiplayer support with server validation
- Added permission system (admins and farm managers)
- Fixed fenced pasture capacity detection (uses actual fence area)

## 0.0.0.1
- Initial alpha
