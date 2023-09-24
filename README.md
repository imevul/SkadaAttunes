# SkadaAttune

A Skada module for tracking attunements

## Dependencies

- Skada

## Installation

1. Download the [latest release](https://github.com/imevul/SkadaAttunes/releases)
2. Extract to Interface/AddOns and enable the addon in-game


## Commands

These commands are completely optional, and can be used to prevent specific items from being tracked by the addon. Replace `<id>` with the itemID you wish to block/unblock.
```
/run SkadaAttunes.addToBlockList(<id>)
/run SkadaAttunes.removeFromBlockList(<id>)
/run print(SkadaAttunes.isInBlockList(<id>))
```
