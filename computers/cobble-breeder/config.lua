-- Breeder settings. 'install update' never replaces this file.
return {
  -- What "better" means. "total": the sum of the six IVs. "perfect": more
  -- 31s wins first, then the total.
  score = "total",
  minGain = 1, -- an egg must beat the breeder's total by at least this much

  keepShiny = true, -- hatch shiny eggs even when they aren't better (no swap)
  nature = nil, -- e.g. "adamant": only eggs with this nature can replace a breeder

  scanRange = 8, -- Scan reads Pokemon sent out this close to the computer
  monitorScale = 0.5, -- text size on the monitor (0.5 fits the most)
}
