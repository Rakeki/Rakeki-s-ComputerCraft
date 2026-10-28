-- Digital Miner manager settings. 'install update' never replaces this file.
return {
  unit = "FE", -- "FE" or "J" (Mekanism joules) for the power each miner uses
  joulesPerFE = 2.5, -- change only if your Mekanism config changes the FE conversion rate

  -- Turn Auto Eject on for every miner when the manager starts (and when a
  -- miner is connected), so mined items flow into the chest at its eject port.
  autoEject = true,

  -- Tags offered as one-tap "+ tag" filter buttons on a miner's page.
  presets = { "c:ores", "c:ores/diamond", "c:ores/iron" },

  -- Names for miners, by peripheral name (shown when you attach a wired
  -- modem, or by 'dminer list'):
  names = {
    -- ["digitalMiner_0"] = "North quarry",
  },
}
