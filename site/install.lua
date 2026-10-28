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
--   install plan <name>                      put a plan in /plans (projector, build-control)
--   install boot                             update what's out of date (every startup.lua runs this)
--
-- On boot, programs installed here are updated when the website has a newer
-- version. 'set install.autoupdate false' turns that off.

local SITE = "{{SITE_URL}}" -- filled in when the website is built
local INSTALLED_FILE = "/.installed" -- programs installed here, for "install update"
local VERSIONS_FILE = "/.installed_versions" -- program -> the version installed, for "install boot"
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
  print("More at " .. SITE)
end

-- Plans are in the manifest as "plan:<name>": installed and updated like
-- programs, into /plans.
local function listPlans(manifest)
  local names = {}
  for name in pairs(manifest.programs) do
    if name:sub(1, 5) == "plan:" then names[#names + 1] = name:sub(6) end
  end
  table.sort(names)
  say("Building plans you can install:", colours.yellow)
  for _, name in ipairs(names) do
    write(("  %-18s"):format(name))
    say(manifest.programs["plan:" .. name].title, colours.lightGrey)
  end
  print()
  print("Install one with: install plan <name>")
end

local function saveSelf()
  local body = fetch("install.lua")
  if body and body ~= readFile(SELF_PATH) then writeFile(SELF_PATH, body) end
end

local function install(manifest, name, updating)
  local program = manifest.programs[name]
  if not program and name:sub(1, 5) == "plan:" then
    say(("There's no plan called '%s'."):format(name:sub(6)), colours.red)
    listPlans(manifest)
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
  markInstalled(name)
  markVersion(name, program.version)
  saveSelf()

  say(("%s is installed."):format(program.title), colours.lime)
  if updating ~= "boot" then
    for _, line in ipairs(program.next or {}) do print(line) end
  end
  return true
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
  local versions, stale = readVersions(), {}
  for _, name in ipairs(installed) do
    local program = manifest.programs[name]
    if program and program.version ~= versions[name] then stale[#stale + 1] = name end
  end
  if #stale == 0 then return say("up to date.", colours.lightGrey) end
  print()
  for _, name in ipairs(stale) do install(manifest, name, "boot") end
end

---------------------------------------------------------------- main

if args[1] == "boot" then return bootUpdate() end

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
  local installed = readInstalled()
  if #installed == 0 then
    print("Nothing has been installed here yet.")
    return
  end
  for _, name in ipairs(installed) do install(manifest, name, true) end
elseif args[1] == "plans" or (args[1] == "plan" and not args[2]) then
  listPlans(manifest)
elseif args[1] == "plan" then
  install(manifest, "plan:" .. args[2], false)
else
  install(manifest, args[1], false)
end
