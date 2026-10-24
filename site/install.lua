-- Installs a program from the website onto this computer or turtle, along with
-- the shared libraries it needs. Every file is downloaded before anything is
-- written, so a failed download never leaves a half-installed program.
--
-- Usage:
--   wget run <site>/install.lua              list the programs
--   wget run <site>/install.lua <program>    install one
--   install <program>                        same, once the installer is saved here
--   install update                           reinstall everything installed here

local SITE = "{{SITE_URL}}" -- filled in when the website is built
local INSTALLED_FILE = "/.installed" -- programs installed here, for "install update"
local SELF_PATH = "/install.lua" -- the installer saves a copy of itself here

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

local function fetch(path)
  local response, err = http.get(SITE .. "/" .. path, nil, true)
  if not response then return nil, err end
  local body = response.readAll()
  response.close()
  return body
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

local function loadManifest()
  local body, err = fetch("manifest.json")
  if not body then
    say("Couldn't reach " .. SITE .. " (" .. tostring(err) .. ").", colours.red)
    return nil
  end
  local manifest = textutils.unserializeJSON(body)
  if not manifest then say("The program list from the website is broken. Try again later.", colours.red) end
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
  print("More at " .. SITE)
end

local function saveSelf()
  local body = fetch("install.lua")
  if body and body ~= readFile(SELF_PATH) then writeFile(SELF_PATH, body) end
end

local function install(manifest, name, updating)
  local program = manifest.programs[name]
  if not program then
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
  saveSelf()

  say(("%s is installed."):format(program.title), colours.lime)
  for _, line in ipairs(program.next or {}) do print(line) end
  return true
end

---------------------------------------------------------------- main

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
else
  install(manifest, args[1], false)
end
