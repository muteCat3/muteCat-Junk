# muteCat Junk

A high-performance, lightweight World of Warcraft addon designed for the **Midnight (12.0.1)** API. Optimized for visual integration with **Baganator**.

## Features

- **Automated Selling**: Instantly sells gray items (junk) and specific low-level bound equipment when interacting with a merchant.
- **Midnight Optimized**: Uses advanced tooltip scraping to bypass item level scaling bugs and ensures accurate evaluation of Timewarped and scaled gear.
- **Smart Logic**: 
  - Keeps all Bind-on-Equip (BoE) items (never accidentally sells gold value).
  - Automatically identifies Soulbound, Accountbound, and Warband-bound gear.
  - Sells old gear based on character level (e.g., Level 90+ sells gear < ILvl 130).
- **Auto-Repair**: Automatically repairs your gear using Guild funds (if available and within limit) or your own gold.
- **Safe Mode**: Hold **Shift** while opening a merchant to temporarily disable auto-selling/repairing.
- **Baganator Ready**: Seamlessly marks junk in your bags using the Baganator Junk Plugin API.

## Installation

1. Download the repository.
2. Place the `muteCat Junk` folder into your `World of Warcraft\_retail_\Interface\AddOns` directory.
3. Restart the game or `/reload` (if the addon was already there).

## Commands

- `/mj`: (Optional) Scans your bags and prints a debug evaluation of all gear items in the chat.

---
*Part of the muteCat Addon Suite.*
