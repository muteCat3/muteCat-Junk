# muteCat Junk

A high-performance, lightweight World of Warcraft addon designed for the **Midnight (12.0.1)** API. Optimized for visual integration with **Baganator**.

## Features

- **Automated Selling**: Instantly sells gray items (junk) and specific low-level bound equipment when interacting with a merchant.
- **Midnight Optimized**: Squish-aware logic for 12.0.1. Corrected thresholds for the massive item level reduction (TWW BiS ~170).
- **Consumables & Mats**: Smart evaluation of crafting reagents and consumables.
  - Keeps all items on the curated **Midnight whitelist**.
  - Sells non-Midnight consumables/mats only if the **Auction House profit (Net AH - Vendor) is < 1 Gold**.
- **Smart Gear Logic**: 
  - Keeps all Bind-on-Equip (BoE) items (never accidentally sells gold value).
  - Automatically identifies Soulbound, Accountbound, and Warband-bound gear.
  - **Profession Gear Protection**: Specifically ignores profession tools and accessories in the material selling logic.
  - Sells old gear based on squish-aware character level thresholds.
- **Auto-Repair**: Automatically repairs your gear using Guild funds (if available and within limit) or your own gold.
- **Safe Mode**: Hold **Shift** while opening a merchant to temporarily disable auto-selling/repairing.
- **Baganator Ready**: Seamlessly marks junk in your bags using the Baganator Junk Plugin API.

## Installation

1. Download the repository.
2. Place the `muteCat Junk` folder into your `World of Warcraft\_retail_\Interface\AddOns` directory.
3. Restart the game or `/reload` (if the addon was already there).

## 1 Gold Rule

To ensure you don't lose gold, the addon calculates the potential profit of selling crafting materials on the Auction House (requires Auctionator). It will **only** vendor items if the net profit (after AH fees) is less than **10,000 Copper (1 Gold)**.

---
*Part of the muteCat Addon Suite.*
