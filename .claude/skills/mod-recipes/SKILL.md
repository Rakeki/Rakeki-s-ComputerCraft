---
name: mod-recipes
description: Getting a modpack's recipes into the programs - the PC-side tools that read the pack's jars (tools/recipes.mjs for crafting, essence-recipes.mjs, saw-recipes.mjs for Create saws), the jars to pass (minecraft, the loader's jar for c: tags, the mods folder), tags, load conditions, the numbered Lua file format, where files go in-game, recipes a mod builds in code at start-up (Create's RuntimeDataGenerator) and how to find them by reading class files. Use when a machine or crafting plan is missing a recipe, when adding a machine whose recipes come from a mod, or when making a pack file.
---

# Modpack recipes

Programs never guess recipes: they come from data. Built-in tables cover
vanilla (and Create for the saw); a modpack's come from its jars, read on
the player's PC by a tool in `tools/` (Node, no dependencies, published on
the site for wget), written as a compact Lua file the computer loads.

| Tool | Reads | Writes | Loaded by |
|---|---|---|---|
| `tools/recipes.mjs` | crafting_shaped / shapeless (+ Cucumber's tag recipes) | `pack_recipes.lua` (`computers/craft-overseer/packs/`) | craft overseer, next to `recipes.lua` |
| `tools/essence-recipes.mjs` | a `pack_recipes.lua` | `essence_recipes.lua` (`computers/factory/packs/`) | the factory's essence part |
| `tools/saw-recipes.mjs` | `create:cutting`, `minecraft:stonecutting`, `*:woodcutting`, + Create's run-time wood recipes | `saw_recipes.lua` (built in) / `saw_pack.lua` (`computers/factory/packs/<pack>-saw.lua`) | the factory's saw part |

## Which jars

Pass **all** of these, in this order (a later jar's recipe with the same id
replaces an earlier one, like datapacks):

1. **`minecraft.jar`**: `versions/1.21.1/1.21.1.jar` in the launcher folder.
2. **The loader's jar**: NeoForge's
   `libraries/net/neoforged/neoforge/<v>/neoforge-<v>-universal.jar` (not
   in the mods folder). It fills the **common `c:` tags**: e.g. it puts
   `minecraft:glass` into `c:glass_blocks/colorless`. Leaving it out lost
   Create's framed glass (its stonecutting recipe takes that tag, and the
   tag then only held Create's own glass). saw-recipes.mjs warns without it.
3. **The mods folder** (or single jars).

The player's CurseForge instances are under
`%USERPROFILE%/curseforge/minecraft/Instances/<pack>/mods`, the launcher's
shared files under `.../curseforge/minecraft/Install/` (versions,
libraries); `minecraftinstance.json` names the loader version.

## Reading recipes right

- **Tags** resolve through every jar's `data/<ns>/tags/item(s)/...json`
  (`replace` clears, `#tag` nests, `{ id, required }` entries).
- **Load conditions** (`neoforge:conditions`, `conditions`): `mod_loaded`
  is checked against the namespaces seen; anything not understood drops
  the recipe (counted in "Left out").
- **Ingredients**: `{ item }`, `{ tag }`, arrays, `neoforge:compound`; a
  custom type (components, NBT) is skipped.
- **Results**: `result.id` (1.21) or `item`; Create's `results[]` may have
  `chance` outputs (byproducts): take the first sure one as what it makes.
- **Item list**: `assets/<ns>/models/item/*.json` (and `items/`) plus every
  tag value and recipe item: what "exists" for rules that check it.

## Recipes no jar contains

Some mods **build recipes in code at start-up**. Create 6 has no data file
for any vanilla log: `com/simibubi/create/foundation/data/RuntimeDataGenerator`
makes, for every item that exists, log/wood/stem/hyphae/block → its
stripped kind (1), stripped → 6 planks (3 for a block: bamboo), and planks
→ stairs, 2 slabs, fence, fence gate, door, trapdoor, pressure plate,
button, sign (only those that exist; `MISMATCHED_WOOD_NAMES` maps a few
planks names). saw-recipes.mjs copies those rules (`STRIPPED_PREFIX`,
`STRIPPED_SUFFIX`, `NON_STRIPPED`, `PIECES`).

When recipes seem missing, look for this: list the jar's `data/<mod>/recipe/<type>/`
(43 files for Create's cutting: only compat ones), then search class files
for the item or method names (`stripped_`, `getAxeStrippingState`). Without
a decompiler, print a class's constant pool strings, or disassemble a method
in a few lines of Node (constant pool, then the `Code` attribute: `ldc` for
strings, `iconst`/`bipush` for counts, `invoke*` for calls), which is how
the counts above were read. Note what a machine does with several
outputs (Create's saw cycles `recipeIndex` unless its filter picks one).

## The file format

Numbered names keep big packs small (1 MB disk):

```lua
-- what wrote it, and the fields
return {names={"minecraft:oak_log", ...},
recipes={
{12,1,3,3},   -- saw: make, count, from, kind (1 Create cutting, 2 stonecutter, 3 Create wood)
}}
```

`pack_recipes.lua` adds `tags` and `{ make, count, rows ("/" between rows),
keys }`. Load with `loadfile(path, "t", {})` in `pcall`, once at start,
and build lookups (`byFrom`, `byKey`) then.

## Where it goes in-game

- A built-in file (`saw_recipes.lua`) is a top-level `.lua` in the program
  folder, so the installer installs and updates it.
- A pack file is published under `packs/` (the installer skips subfolders)
  and fetched by the player under a name the installer **never ships**
  (`saw_pack.lua`, `pack_recipes.lua`), so updates never overwrite it:
  `wget <site>/computers/factory/packs/atmons-saw.lua saw_pack.lua`.
- Commit regenerated files with the tool change; say in the README how
  many recipes and how big.

Related: [[factory]], [[storage-system]] (the overseer's recipes, `reach`),
[[performance]] (big data).
