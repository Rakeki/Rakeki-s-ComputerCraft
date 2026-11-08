-- Installs a program from the website onto this computer or turtle, along with
-- the shared libraries it needs. Every file is downloaded before anything is
-- written, so a failed download never leaves a half-installed program.
--
-- Usage:
--   wget run <site>/install.lua              list the programs
--   wget run <site>/install.lua <program>    install one
--   install <program>                        same, once the installer is saved here
--   install update                           reinstall everything installed here
--   install plans                            list the building plans
--   install plan <name> [<name> ...]         put plans in /plans (projector, build-control)
--   install remove <program>                 uninstall a program (also: install uninstall)
--   install remove plan <name>               remove a plan
--   install animations                       list the animations for the display monitor
--   install animation <name> [<name> ...]    put animations in /animations (display-monitor)
--   install remove animation <name>          remove an animation
--   install remove                           list what's installed here
--   install boot                             update what's out of date (every startup.lua runs this)
--
-- On boot, programs installed here are updated when the website has a newer
-- version. 'set install.autoupdate false' turns that off.

local SITE = "{{SITE_URL}}" -- filled in when the website is built
local INSTALLED_FILE = "/.installed" -- programs installed here, for "install update"
local VERSIONS_FILE = "/.installed_versions" -- program -> the version installed, for "install boot"
local FILES_FILE = "/.installed_files" -- program -> the files it put here, so an update can remove ones it dropped
local SELF_PATH = "/install.lua" -- the installer saves a copy of itself here
local AUTO_SETTING = "install.autoupdate" -- false: don't check for updates on boot
local TIMEOUT = 20 -- seconds to wait for each download
local BOOT_TIMEOUT = 5 -- seconds to wait for the website on boot before carrying on without it

if settings.define then
  settings.define(AUTO_SETTING, {
    description = "Update installed programs from the website on every boot.",
    default = true, type = "boolean",
  })
end

local args = { ... }

---------------------------------------------------------------- output

local function say(text, colour)
  if colour and term.isColour() then term.setTextColour(colour) end
  print(text)
  term.setTextColour(colours.white)
end

local function ask(question)
  if term.isColour() then term.setTextColour(colours.yellow) end
  write(question .. " (y/n) ")
  term.setTextColour(colours.white)
  local answer = read()
  return answer:lower():sub(1, 1) == "y"
end

---------------------------------------------------------------- download

-- http.get can hang for a long time when the website can't be reached, so
-- ask in the background and give up after a deadline.
local function fetch(path, timeout)
  local url = SITE .. "/" .. path
  local ok, err = http.request({ url = url, binary = true })
  if not ok then return nil, err end
  local timer = os.startTimer(timeout or TIMEOUT)
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "http_success" and a == url then
      os.cancelTimer(timer)
      local body = b.readAll()
      b.close()
      return body
    elseif event == "http_failure" and a == url then
      os.cancelTimer(timer)
      if c then c.close() end
      return nil, b
    elseif event == "timer" and a == timer then
      return nil, "timed out"
    end
  end
end

local function writeFile(path, body)
  local f = fs.open(path, "wb")
  f.write(body)
  f.close()
end

local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "rb")
  local body = f.readAll()
  f.close()
  return body
end

-- quiet: say nothing when it fails (a boot check just carries on)
local function loadManifest(timeout, quiet)
  local body, err = fetch("manifest.json", timeout)
  if not body then
    if not quiet then say("Couldn't reach " .. SITE .. " (" .. tostring(err) .. ").", colours.red) end
    return nil
  end
  local manifest = textutils.unserializeJSON(body)
  if not manifest and not quiet then say("The program list from the website is broken. Try again later.", colours.red) end
  return manifest
end

---------------------------------------------------------------- installed list

local function readInstalled()
  local body = readFile(INSTALLED_FILE)
  return body and textutils.unserialize(body) or {}
end

local function markInstalled(name)
  local installed = readInstalled()
  for _, n in ipairs(installed) do
    if n == name then return end
  end
  installed[#installed + 1] = name
  writeFile(INSTALLED_FILE, textutils.serialize(installed))
end

local function readVersions()
  local body = readFile(VERSIONS_FILE)
  return body and textutils.unserialize(body) or {}
end

local function markVersion(name, version)
  local versions = readVersions()
  versions[name] = version
  writeFile(VERSIONS_FILE, textutils.serialize(versions))
end

local function readFiles()
  local body = readFile(FILES_FILE)
  return body and textutils.unserialize(body) or {}
end

-- Files that an earlier install put here can be replaced without asking.
local function ownedFiles(manifest)
  local owned = {}
  for _, name in ipairs(readInstalled()) do
    local program = manifest.programs[name]
    if program then
      for _, file in ipairs(program.files) do owned[file.dest] = true end
    end
  end
  return owned
end

---------------------------------------------------------------- commands

local function listPrograms(manifest)
  say("Programs you can install:", colours.yellow)
  for _, name in ipairs(manifest.order) do
    local program = manifest.programs[name]
    write(("  %-18s"):format(name))
    say(program.device, colours.lightGrey)
  end
  print()
  print("Install one with: install <program>")
  print("Building plans: install plans")
  print("Animations for the display: install animations")
  print("Uninstall one with: install remove <program>")
  print("More at " .. SITE)
end

-- Plans and animations are in the manifest as "plan:<name>" and
-- "animation:<name>": installed and updated like programs, into /plans and
-- /animations. KINDS says how each is listed.
local KINDS = {
  plan = { heading = "Building plans you can install:", page = "/plans/", what = "Pictures of each" },
  animation = { heading = "Animations for the display monitor:", page = "/programs/display-monitor/#animations", what = "See them play" },
}

-- "plan:bunker" -> "plan", "bunker"; nil, nil for a program
local function kindOf(name)
  local kind, rest = name:match("^(%a+):(.+)$")
  if kind and KINDS[kind] then return kind, rest end
end

-- "plan:bunker" -> "plan bunker", as typed after 'install' / 'install remove'
local function typed(name)
  local kind, rest = kindOf(name)
  return kind and (kind .. " " .. rest) or name
end

local function listKind(manifest, kind)
  local names = {}
  for name in pairs(manifest.programs) do
    local k, rest = kindOf(name)
    if k == kind then names[#names + 1] = rest end
  end
  table.sort(names)
  local info = KINDS[kind]
  say(info.heading, colours.yellow)
  -- columns, a page at a time: there are too many for a line each
  textutils.pagedTabulate(term.isColour() and colours.lightGrey or colours.white, names)
  term.setTextColour(colours.white)
  print(info.what .. ": " .. SITE .. info.page)
  print(("Install one with: install %s <name>"):format(kind))
  print(("or several: install %s <name> <name> ..."):format(kind))
end

local function saveSelf()
  local body = fetch("install.lua")
  if body and body ~= readFile(SELF_PATH) then writeFile(SELF_PATH, body) end
end

-- Files the last version of this program put here that the new one doesn't
-- have any more go, unless another installed program still has them (a
-- shared lib). Then what this version put here is recorded for next time.
local function removeDropped(manifest, name, program)
  local record = readFiles()
  local now, others = {}, {}
  for _, file in ipairs(program.files) do now[file.dest] = true end
  for _, other in ipairs(readInstalled()) do
    if other ~= name then
      for _, file in ipairs(manifest.programs[other] and manifest.programs[other].files or {}) do others[file.dest] = true end
      for _, dest in ipairs(record[other] or {}) do others[dest] = true end
    end
  end
  -- Plans a program used to come with stay, recorded as installed plans
  -- from now on, so a player's plans don't vanish when the program updates.
  local planOf = {}
  for key, other in pairs(manifest.programs) do
    if key:sub(1, 5) == "plan:" then
      for _, file in ipairs(other.files) do planOf[file.dest] = key end
    end
  end
  local adopted = {}
  for _, dest in ipairs(record[name] or {}) do
    if not now[dest] and not others[dest] and fs.exists(dest) then
      if planOf[dest] then
        record[planOf[dest]] = { dest }
        adopted[#adopted + 1] = planOf[dest]
      else
        fs.delete(dest)
      end
    end
  end
  local list = {}
  for _, file in ipairs(program.files) do list[#list + 1] = file.dest end
  record[name] = list
  writeFile(FILES_FILE, textutils.serialize(record))
  -- no version saved for them, so the next update fetches each plan's latest
  for _, key in ipairs(adopted) do markInstalled(key) end
end

local function install(manifest, name, updating)
  local program = manifest.programs[name]
  -- 'install smelter-computer' installs what took its place
  if program and program.alias and manifest.programs[program.alias] then
    if not updating then say(("%s is part of %s now."):format(name, program.alias), colours.lightGrey) end
    name, program = program.alias, manifest.programs[program.alias]
  end
  if not program and kindOf(name) then
    local kind, rest = kindOf(name)
    say(("There's no %s called '%s'."):format(kind, rest), colours.red)
    listKind(manifest, kind)
    return false
  elseif not program then
    say(("There's no program called '%s'."):format(name), colours.red)
    listPrograms(manifest)
    return false
  end

  if not updating then
    if program.device == "turtle" and not turtle then
      if not ask(program.title .. " is a turtle program, and this isn't a turtle. Install anyway?") then return false end
    end
    local owned, replacing = ownedFiles(manifest), {}
    for _, file in ipairs(program.files) do
      if fs.exists(file.dest) and not owned[file.dest] and not file.keep then
        replacing[#replacing + 1] = file.dest
      end
    end
    if #replacing > 0 then
      say("These files are already here and will be replaced:", colours.orange)
      print("  " .. table.concat(replacing, ", "))
      if not ask("Carry on?") then return false end
    end
  end

  say(("Installing %s..."):format(program.title), colours.yellow)
  local bodies = {}
  for i, file in ipairs(program.files) do
    if file.keep and fs.exists(file.dest) then
      say(("  Kept your %s"):format(file.dest), colours.lightGrey)
    else
      write(("  %s "):format(file.dest))
      local body, err = fetch(file.src)
      if not body then
        say("failed", colours.red)
        say(("Couldn't download %s: %s. Nothing was changed."):format(file.dest, tostring(err)), colours.red)
        return false
      end
      bodies[i] = body
      say("ok", colours.lime)
    end
  end

  for i, file in ipairs(program.files) do
    if bodies[i] then writeFile(file.dest, bodies[i]) end
  end
  removeDropped(manifest, name, program)
  markInstalled(name)
  markVersion(name, program.version)
  saveSelf()

  say(("%s is installed."):format(program.title), colours.lime)
  if updating ~= "boot" then
    for _, line in ipairs(program.next or {}) do print(line) end
  end
  return true
end

-- A program that another took the place of (the manifest gives it an alias,
-- e.g. the smelter is part of the factory now) is recorded under the new
-- name from now on: an install under the old name put the new one's files here.
local function renameAliases(manifest)
  local installed, versions, record = readInstalled(), readVersions(), readFiles()
  local list, seen, changed = {}, {}, false
  for _, name in ipairs(installed) do
    local program = manifest.programs[name]
    local new = program and program.alias
    if new then
      changed = true
      versions[new] = versions[new] or versions[name]
      record[new] = record[new] or record[name]
      versions[name], record[name] = nil, nil
      name = new
    end
    if not seen[name] then
      seen[name] = true
      list[#list + 1] = name
    end
  end
  if not changed then return end
  writeFile(INSTALLED_FILE, textutils.serialize(list))
  writeFile(VERSIONS_FILE, textutils.serialize(versions))
  writeFile(FILES_FILE, textutils.serialize(record))
end

-- On boot: update only the programs the website has a newer version of, and
-- carry on quickly when it can't be reached.
local function bootUpdate()
  if settings.get(AUTO_SETTING) == false then return end
  local installed = readInstalled()
  if not http or #installed == 0 then return end
  write("Checking for updates... ")
  local manifest = loadManifest(BOOT_TIMEOUT, true)
  if not manifest then return say("couldn't reach the website, carrying on.", colours.lightGrey) end
  renameAliases(manifest)
  installed = readInstalled()
  local versions, stale = readVersions(), {}
  for _, name in ipairs(installed) do
    local program = manifest.programs[name]
    if program and program.version ~= versions[name] then stale[#stale + 1] = name end
  end
  if #stale == 0 then return say("up to date.", colours.lightGrey) end
  print()
  for _, name in ipairs(stale) do install(manifest, name, "boot") end
end

---------------------------------------------------------------- uninstalling

-- What's installed here, plans shown as "plan <name>" (animations likewise).
local function listInstalled()
  local installed = readInstalled()
  if #installed == 0 then return print("Nothing has been installed here.") end
  say("Installed here:", colours.yellow)
  for _, name in ipairs(installed) do
    print("  " .. typed(name))
  end
  print()
  print("Uninstall one with: install remove <program>")
  print("or: install remove plan <name>, install remove animation <name>")
end

-- Delete a folder the uninstall left empty (/lib, /plans, /animations).
local function removeIfEmpty(dir)
  if fs.isDir(dir) and #fs.list(dir) == 0 then fs.delete(dir) end
end

-- Uninstall a program (or "plan:<name>", "animation:<name>"): its files go, except ones another
-- installed program still uses (a shared lib or plan) and, unless you say
-- so, your settings. The website is only needed for programs installed
-- before the installer kept a list of their files.
local function remove(name)
  local installed = readInstalled()
  local here = false
  for _, n in ipairs(installed) do
    if n == name then here = true end
  end
  if not here then
    local kind, rest = kindOf(name)
    say(("%s isn't installed here."):format(kind and ("The " .. kind .. " '" .. rest .. "'") or ("'" .. name .. "'")), colours.red)
    return listInstalled()
  end

  local record = readFiles()
  -- the program list says which files are settings, and knows older installs' files
  local manifest = http and loadManifest(BOOT_TIMEOUT, true)
  local program = manifest and manifest.programs[name]
  local files = record[name]
  if not files and program then
    files = {}
    for _, file in ipairs(program.files) do files[#files + 1] = file.dest end
  end
  if not files then
    say("I don't know which files it put here: it was installed before the installer kept a list,", colours.red)
    say("and the website can't be reached. Try again when it can.", colours.red)
    return false
  end
  local settingsFile = {}
  for _, file in ipairs(program and program.files or {}) do
    if file.keep then settingsFile[file.dest] = true end
  end
  if not program then settingsFile["config.lua"] = true end

  -- files other installed programs use stay
  local others = {}
  for _, other in ipairs(installed) do
    if other ~= name then
      for _, dest in ipairs(record[other] or {}) do others[dest] = true end
      local op = manifest and manifest.programs[other]
      for _, file in ipairs(op and op.files or {}) do others[file.dest] = true end
    end
  end
  local gone, shared, settings = {}, {}, {}
  for _, dest in ipairs(files) do
    if others[dest] then
      shared[#shared + 1] = dest
    elseif fs.exists(dest) then
      if settingsFile[dest] then settings[#settings + 1] = dest else gone[#gone + 1] = dest end
    end
  end

  local title = program and program.title or (kindOf(name) and ("the " .. typed(name)) or name)
  say(("Uninstalling %s:"):format(title), colours.yellow)
  if #gone > 0 then print("  deletes " .. table.concat(gone, ", ")) end
  if #shared > 0 then print("  keeps " .. table.concat(shared, ", ") .. " (other programs here use them)") end
  if not ask("Carry on?") then return false end
  if #settings > 0 and ask(("Delete your settings too (%s)?"):format(table.concat(settings, ", "))) then
    for _, dest in ipairs(settings) do gone[#gone + 1] = dest end
    settings = {}
  end

  for _, dest in ipairs(gone) do fs.delete(dest) end
  removeIfEmpty("lib")
  removeIfEmpty("plans")
  removeIfEmpty("animations")
  local left = {}
  for _, n in ipairs(installed) do
    if n ~= name then left[#left + 1] = n end
  end
  writeFile(INSTALLED_FILE, textutils.serialize(left))
  local versions = readVersions()
  versions[name] = nil
  writeFile(VERSIONS_FILE, textutils.serialize(versions))
  record[name] = nil
  writeFile(FILES_FILE, textutils.serialize(record))

  say(("%s is uninstalled."):format(title:sub(1, 1):upper() .. title:sub(2)), colours.lime)
  if #settings > 0 then print("Your settings are still here: " .. table.concat(settings, ", ")) end
  if #shared > 0 then print("If another program here stops starting on boot, 'install update' puts its files back.") end
  return true
end

---------------------------------------------------------------- main

if args[1] == "boot" then return bootUpdate() end
if args[1] == "remove" or args[1] == "uninstall" then
  if not args[2] then return listInstalled() end
  if KINDS[args[2]] then
    if not args[3] then return listInstalled() end
    return remove(args[2] .. ":" .. args[3])
  end
  return remove(args[2])
end

if not http then
  say("This computer can't reach the internet: http is turned off in the", colours.red)
  say("ComputerCraft config. Ask whoever runs the server to enable it.", colours.red)
  return
end

local manifest = loadManifest()
if not manifest then return end

if #args == 0 or args[1] == "list" then
  listPrograms(manifest)
elseif args[1] == "update" then
  renameAliases(manifest)
  local installed = readInstalled()
  if #installed == 0 then
    print("Nothing has been installed here yet.")
    return
  end
  for _, name in ipairs(installed) do install(manifest, name, true) end
elseif args[1] == "plans" or args[1] == "animations" or (KINDS[args[1]] and not args[2]) then
  listKind(manifest, args[1] == "plans" and "plan" or args[1] == "animations" and "animation" or args[1])
elseif KINDS[args[1]] then
  -- several at once, as the website's plans page writes them
  for i = 2, #args do install(manifest, args[1] .. ":" .. args[i], false) end
else
  install(manifest, args[1], false)
end
