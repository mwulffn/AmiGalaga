-- Log every sound driver tick: what the main CPU asked for, what the sound
-- CPU wrote to the sound chip. One 53-byte record per tick:
--   $9aa0-$9abf (requests), $9a79 (new credits), $9211 (formation direction)
--   as the sound CPU read them during the tick,
--   $6810-$681f (frequency and volume registers), wave select of voices 0-2
local total = tonumber(os.getenv("GFRAMES") or "40000")
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local snd = m.devices[":sub2"].spaces["program"]
local fields = {}
for _, port in pairs(m.ioport.ports) do
  for name, f in pairs(port.fields) do fields[name] = f end
end
local function set(name, v) local f = fields[name]; if f then f:set_value(v) end end
local out = io.open(os.getenv("GOUT") or "sound.bin", "wb")
local regs, seen, ticking = {}, {}, false
for i = 0, 31 do regs[i] = 0 end

-- The main CPU can set a request in the middle of a tick, so record what the
-- driver actually read (the first read of each byte), not a snapshot.
local function first_read(key)
  return function(offset, data, mask)
    if ticking and seen[key + offset] == nil then seen[key + offset] = data & 0xff end
  end
end
_G.__tap0 = snd:install_read_tap(0x9aa0, 0x9abf, "requests", first_read(0))
_G.__tap3 = snd:install_read_tap(0x9a79, 0x9a79, "credits", first_read(0))
_G.__tap4 = snd:install_read_tap(0x9211, 0x9211, "formation", first_read(0))

_G.__tap1 = snd:install_write_tap(0x6800, 0x681f, "wsg", function(offset, data, mask)
  local r = offset - 0x6800
  regs[r] = data & 0xff
  if r == 0x0f and ticking then -- the driver's last write of a tick
    local t = {}
    for a = 0x9aa0, 0x9abf do t[#t + 1] = string.char(seen[a] or mem:read_u8(a)) end
    t[#t + 1] = string.char(seen[0x9a79] or mem:read_u8(0x9a79), seen[0x9211] or mem:read_u8(0x9211))
    for i = 0x10, 0x1f do t[#t + 1] = string.char(regs[i]) end
    out:write(table.concat(t), string.char(regs[0x05], regs[0x0a], regs[0x0f]))
    ticking = false
  end
end)
_G.__tap2 = snd:install_write_tap(0x6822, 0x6822, "nmiack", function(offset, data, mask)
  if (data & 1) == 1 then seen, ticking = {}, true end -- start of the tick
end)

local frame = 0
local function tick()
  frame = frame + 1
  set("Coin 1", (frame >= 1200 and frame < 1210) and 1 or 0)
  set("1 Player Start", (frame >= 1400 and frame < 1410) and 1 or 0)
  if frame > 1600 then
    local ph = (frame // 70) % 4
    set("P1 Left", (ph == 0 or ph == 3) and 1 or 0)
    set("P1 Right", (ph == 1 or ph == 2) and 1 or 0)
    set("P1 Button 1", (frame % 6 < 3) and 1 or 0)
    mem:write_u8(0x9820, 3)
  end
  if frame >= total then out:close(); m:exit() end
end
_G.__sub = emu.add_machine_frame_notifier(tick)
