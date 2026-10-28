-- Fission guard settings. 'install update' never replaces this file.
-- Fill levels are fractions: 0.10 is 10%.
return {
  -- SCRAM when any of these is reached. Mekanism starts damaging the
  -- reactor above 1200 K and it can melt down at 100% damage.
  maxTemp = 1000, -- kelvin
  maxDamage = 1, -- percent
  minCoolant = 0.10, -- coolant tank this empty or emptier
  maxHeated = 0.90, -- heated coolant (steam) tank this full: the boilers or turbines can't keep up
  maxWaste = 0.80, -- waste tank this full: nothing is taking the waste away

  lowFuel = 0.05, -- only a warning on screen: an empty reactor just stops

  -- With an Induction Port connected: pause the reactor when the matrix is
  -- this full and start it again below resumePowerBelow. false: never pause.
  pausePowerAt = 0.98,
  resumePowerBelow = 0.80,

  alarm = true, -- ring a speaker (if there is one) while a SCRAM is latched
  alarmSide = nil, -- e.g. "back": a redstone signal on that side while latched (lamps, Mekanism's industrial alarm)
}
