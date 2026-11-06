// Stand-ins for the mod blocks some programs drive: Mekanism's Induction
// Matrix, fission and fusion reactors and Digital Miners (method names from
// Mekanism 10.7's methods.csv), and Advanced Peripherals' Colony Integrator.
// Each keeps a little state and changes over time, so the programs have
// something to react to.
import { Peripheral } from "./world.mjs";
import { LuaError, multi } from "./vm.mjs";

// a peripheral whose every method is a main-thread call (Mekanism's are)
function device(types, methods) {
  const m = {};
  for (const [k, v] of Object.entries(methods)) m[k] = typeof v === "function" ? (ctx, ...a) => v(...a) : () => v;
  return new Peripheral(types, m, { mainThread: true });
}

//---------------------------------------------------------------- power

// An Induction Matrix; returns { matrix, ports: [Peripheral] }. Energy in joules.
export function inductionMatrix(w, opts = {}) {
  const m = { energy: opts.energy ?? 4e9, max: opts.max ?? 8e9, input: opts.input ?? 40000, output: opts.output ?? 30000, minPos: opts.minPos || { x: 100, y: 64, z: -40 } };
  w.addTicker((dt) => {
    // input and output wander, as generators and machines come and go
    const t = w.time;
    m.lastIn = m.input * (1 + 0.3 * Math.sin(t / 37));
    m.lastOut = m.output * (1 + 0.5 * Math.sin(t / 23 + 1));
    m.energy = Math.max(0, Math.min(m.max, m.energy + (m.lastIn - m.lastOut) * 20 * dt));
  });
  const port = () => device(["inductionPort"], {
    isFormed: true, getEnergy: () => m.energy, getMaxEnergy: () => m.max, getEnergyFilledPercentage: () => m.energy / m.max,
    getLastInput: () => m.lastIn ?? m.input, getLastOutput: () => m.lastOut ?? m.output, getTransferCap: 2.56e8,
    getInstalledCells: 8, getInstalledProviders: 4, getMinPos: () => m.minPos,
  });
  return { matrix: m, port };
}

//---------------------------------------------------------------- fission

// A fission reactor that heats up while it burns and cools with coolant.
// `coolantRunsOutAt` (seconds) makes the coolant supply stop then, so the
// guard has something to SCRAM for.
export function fissionReactor(w, opts = {}) {
  const r = { active: false, burn: 1, maxBurn: 20, temp: 300, damage: 0, coolant: 1, heated: 0, waste: 0, fuel: 0.9, forceDisabled: false, scrams: 0, starts: 0 };
  w.addTicker((dt) => {
    const supply = !(opts.coolantRunsOutAt && w.time > opts.coolantRunsOutAt);
    if (r.active) {
      r.fuel = Math.max(0, r.fuel - r.burn * 1e-5 * dt);
      r.waste = Math.min(1, r.waste + r.burn * 2e-5 * dt);
      r.coolant = Math.max(0, r.coolant - r.burn * 0.004 * dt + (supply ? r.burn * 0.004 * dt : 0));
      r.heated = Math.min(1, r.heated + 0.001 * dt);
      const target = r.coolant > 0.05 ? 450 + r.burn * 20 : 300 + r.burn * 120;
      r.temp += (target - r.temp) * Math.min(1, 0.08 * dt);
      if (r.fuel <= 0) r.active = false;
    } else {
      r.temp += (300 - r.temp) * Math.min(1, 0.03 * dt);
      if (supply) r.coolant = Math.min(1, r.coolant + 0.01 * dt);
    }
    r.heated = Math.max(0, r.heated - 0.002 * dt);
    if (r.temp > 1200) r.damage = Math.min(100, r.damage + (r.temp - 1200) * 0.001 * dt);
  });
  const port = (type) => device([type], {
    isFormed: true, getStatus: () => r.active, isForceDisabled: () => r.forceDisabled,
    getTemperature: () => r.temp, getDamagePercent: () => r.damage, getCoolantFilledPercentage: () => r.coolant,
    getHeatedCoolantFilledPercentage: () => r.heated, getWasteFilledPercentage: () => r.waste, getFuelFilledPercentage: () => r.fuel,
    getBurnRate: () => r.burn, getActualBurnRate: () => (r.active ? r.burn : 0), getMaxBurnRate: () => r.maxBurn,
    getHeatingRate: () => (r.active ? r.burn * 20000 : 0),
    activate: () => { if (r.active) throw new LuaError("Reactor is already active."); if (r.damage >= 100) throw new LuaError("Reactor is damaged."); r.active = true; r.starts++; },
    scram: () => { if (!r.active) throw new LuaError("Scram requires the reactor to be active."); r.active = false; r.scrams++; },
    setBurnRate: (n) => { if (typeof n !== "number" || n < 0 || n > r.maxBurn) throw new LuaError(`Burn rate must be between 0 and ${r.maxBurn}.`); r.burn = n; },
  });
  return { reactor: r, port };
}

//---------------------------------------------------------------- fusion

export function fusionReactor(w) {
  const f = { injection: 2, plasma: 0, casing: 0, ignited: false };
  w.addTicker((dt) => {
    f.plasma += ((f.injection > 0 ? 1.2e8 + f.injection * 2e7 : 0) - f.plasma) * Math.min(1, 0.05 * dt);
    f.casing += (f.plasma / 100 - f.casing) * Math.min(1, 0.05 * dt);
    f.ignited = f.plasma > 1e8;
  });
  return {
    fusion: f,
    port: (type) => device([type], {
      isFormed: true, isIgnited: () => f.ignited, getPlasmaTemperature: () => f.plasma, getCaseTemperature: () => f.casing,
      getMaxPlasmaTemperature: 5e8, getMaxCasingTemperature: 5e6, getIgnitionTemperature: 1e8,
      getInjectionRate: () => f.injection, getMinInjectionRate: 2, getProductionRate: () => (f.ignited ? f.injection * 1.5e5 : 0),
      getDeuteriumFilledPercentage: 0.8, getTritiumFilledPercentage: 0.75, getDTFuelFilledPercentage: 0.6,
      getWaterFilledPercentage: 0.95, getSteamFilledPercentage: 0.2, getWater: { name: "minecraft:water", amount: 950000 },
      getHohlraum: { name: "mekanism:hohlraum", count: 1 },
      setInjectionRate: (n) => { if (n % 2 !== 0 || n < 0 || n > 98) throw new LuaError("Injection rate must be an even number from 0 to 98."); f.injection = n; },
    }),
  };
}

//---------------------------------------------------------------- digital miners

export function digitalMiner(w, n = 0) {
  const d = { running: false, radius: 16, minY: -59, maxY: 60, silk: false, autoEject: false, toMine: 12000 + n * 1000, filters: [], mined: 0 };
  w.addTicker((dt) => { if (d.running && d.toMine > 0) { const k = Math.min(d.toMine, Math.round(2 * dt)); d.toMine -= k; d.mined += k; } });
  const p = device(["digitalMiner"], {
    getState: () => (d.running ? (d.toMine > 0 ? "SEARCHING" : "FINISHED") : "IDLE"), isRunning: () => d.running,
    start: () => { d.running = true; }, stop: () => { d.running = false; }, reset: () => { d.running = false; d.toMine = 12000; },
    getRadius: () => d.radius, setRadius: (r) => { if (r < 1 || r > 32) throw new LuaError("Radius must be between 1 and 32."); d.radius = r; d.toMine = r * r * 30; },
    getMaxRadius: 32, getMinY: () => d.minY, setMinY: (y) => { d.minY = y; }, getMaxY: () => d.maxY, setMaxY: (y) => { d.maxY = y; },
    getSilkTouch: () => d.silk, setSilkTouch: (b) => { d.silk = !!b; }, getAutoEject: () => d.autoEject, setAutoEject: (b) => { d.autoEject = !!b; },
    getToMine: () => d.toMine, getEnergyFilledPercentage: 0.9, getEnergyUsage: () => (d.running ? 2000 : 0),
    getFilters: () => d.filters, addFilter: (f) => { d.filters.push(f); return true; }, removeFilter: (f) => { d.filters = d.filters.filter((x) => JSON.stringify(x) !== JSON.stringify(f)); return true; },
    getItemStack: () => null, getReplaceTarget: () => null, getRequiresReplacement: false, isEnabled: true,
  });
  p.state = d;
  return p;
}

//---------------------------------------------------------------- colony

export function colonyIntegrator(w) {
  const citizens = ["Ada", "Bram", "Cora", "Dov", "Elin", "Faro", "Gus"].map((name, i) => ({
    id: i + 1, name: `${name} Miller`, job: ["Builder", "Farmer", "Miner", "Courier", "Guard", "Cook", "Unemployed"][i],
    happiness: 6 + (i % 4), health: 20 - i, maxHealth: 20, saturation: 10 - i, betterFood: i === 3, isAsleep: false, location: { x: 200 + i, y: 64, z: 200 },
    work: i < 6 ? { type: "work", location: { x: 210, y: 64, z: 200 + i } } : null, home: { location: { x: 220, y: 64, z: 200 + i } },
    state: i === 6 ? "Idle" : "Working",
  }));
  return device(["colony_integrator", "colonyIntegrator"], {
    isInColony: true, getColonyName: "Simsville", amountOfCitizens: citizens.length, maxOfCitizens: 12, amountOfGraves: 0, amountOfConstructionSites: 1, getColonyID: 1, getHappiness: 7.4, isActive: true, isUnderAttack: () => w.time % 900 > 840,
    getLocation: { x: 200, y: 64, z: 200 },
    getCitizens: citizens,
    getBuildings: [
      { type: "townhall", name: "Town Hall", level: 2, maxLevel: 5, built: true, isWorkingOn: false, location: { x: 205, y: 64, z: 205 }, citizens: [] },
      { type: "builder", name: "Builder's Hut", level: 1, maxLevel: 5, built: true, isWorkingOn: true, location: { x: 210, y: 64, z: 200 }, citizens: [{ id: 1 }] },
      { type: "farmer", name: "Farm", level: 1, maxLevel: 5, built: true, isWorkingOn: false, location: { x: 214, y: 64, z: 200 }, citizens: [{ id: 2 }] },
    ],
    getRequests: [{ id: "r1", name: "Oak Planks", desc: "Builder needs 32 oak planks", count: 32, minCount: 16, target: "Ada Miller", state: "IN_PROGRESS", items: [{ name: "minecraft:oak_planks", count: 32 }] }],
    getWorkOrders: [{ id: 1, buildingName: "Farm", type: "UPGRADE", targetLevel: 2, priority: 1, isClaimed: true, builder: { x: 210, y: 64, z: 200 } }],
  });
}

//---------------------------------------------------------------- Create

// A Schematicannon with a schematic loaded: it takes one block at a time
// from the chest touching it, in order, and stops when one is missing. The
// Block Reader next to it reports its block data the way Advanced
// Peripherals does (State, Status, MissingItem, AmountPlaced, AmountToPlace).
export function schematicannon(w, cannonPos, chestInv, needs) {
  const queue = [];
  for (const [name, n] of Object.entries(needs)) for (let i = 0; i < n; i++) queue.push(name.includes(":") ? name : "minecraft:" + name);
  const c = { total: queue.length, placed: 0, state: "RUNNING", status: "placing", missing: null, gunpowder: 0 };
  w.setBlock(...cannonPos, "create:schematicannon");
  w.addTicker((dt) => {
    for (let k = 0; k < Math.round(dt * 2) && c.placed < c.total; k++) {
      const want = queue[c.placed];
      const slot = chestInv.slots.findIndex((s) => s && s.name === want);
      if (slot < 0) { c.status = "missingBlock"; c.missing = { id: want, count: 1 }; return; }
      chestInv.take(slot, 1);
      c.placed++; c.status = "placing"; c.missing = null;
    }
    if (c.placed >= c.total) { c.state = "STOPPED"; c.status = "finished"; }
  });
  const reader = new Peripheral(["block_reader"], {
    getBlockName: () => "create:schematicannon",
    getBlockData: () => ({ State: c.state, Status: c.status, MissingItem: c.missing || { id: "minecraft:air", count: 0 }, AmountPlaced: c.placed, AmountToPlace: c.total, RemainingFuel: 100 }),
    getBlockStates: () => ({ facing: "north" }),
  }, { mainThread: true });
  return { cannon: c, reader };
}
