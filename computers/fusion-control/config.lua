-- Fusion control settings. 'install update' never replaces this file.
-- Fill levels are fractions: 0.10 is 10%.
return {
  unit = "FE", -- "FE" or "J" (Mekanism joules)
  joulesPerFE = 2.5, -- change only if your Mekanism config changes the FE conversion rate

  lowFuel = 0.10, -- warn when the deuterium or tritium tank is this low
  lowWater = 0.10, -- warn when a water-cooled reactor's water is this low
  hotCase = 0.90, -- warn when the case reaches this share of its maximum temperature

  alarm = true, -- beep a speaker (if there is one) when the reaction goes out
}
