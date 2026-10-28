-- Power dashboard settings. 'install update' never replaces this file.
-- Fill levels are fractions: 0.20 is 20%.
return {
  unit = "FE", -- "FE" or "J" (Mekanism joules)
  joulesPerFE = 2.5, -- change only if your Mekanism config changes the FE conversion rate

  graphMinutes = 60, -- how far back the graph goes

  -- A redstone signal while power is low, e.g. to switch generators on.
  -- It turns on at or below signalOn and off again at or above signalOff.
  signalSide = nil, -- e.g. "back"; nil for no signal
  signalOn = 0.20,
  signalOff = 0.90,

  alertBelow = 0.05, -- the status server shows an alert below this

  -- Names for turbines and cubes, by peripheral name (shown when you attach
  -- a wired modem, or run 'peripherals'):
  names = {
    -- ["turbineValve_0"] = "Main turbine",
    -- ["ultimateEnergyCube_2"] = "Base backup",
  },
}
