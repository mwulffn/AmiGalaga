-- Record the noise chip on its own. Use with MAME's -wavwrite.
-- The tone chip is kept silent (the sound driver's own "reset" flag), the bot
-- plays without firing so the fighter keeps getting destroyed, and every
-- explosion command sent to the noise chip is logged with its time.
local total = tonumber(os.getenv("GFRAMES") or "20000")
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local fields = {}
for _, port in pairs(m.ioport.ports) do
  for name, f in pairs(port.fields) do fields[name] = f end
end
local function set(name, v) local f = fields[name]; if f then f:set_value(v) end end
local out = io.open(os.getenv("GOUT") or "noise_events.txt", "w")
local params = {}

_G.__tap1 = mem:install_write_tap(0x7000, 0x7000, "iodata", function(offset, data, mask)
  params[#params + 1] = string.format("%02x", data & 0xff)
end)
_G.__tap2 = mem:install_write_tap(0x7100, 0x7100, "iocmd", function(offset, data, mask)
  if (data & 0xff) == 0xa8 then
    out:write(string.format("%.6f bang\n", m.time:as_double()))
    params = {}
  elseif (data & 0xff) == 0x10 and #params > 0 then
    out:write(string.format("%.6f params %s\n", m.time:as_double(), table.concat(params, " ")))
    params = {}
  else
    params = {}
  end
end)

local frame = 0
local function tick()
  frame = frame + 1
  set("Coin 1", (frame >= 1200 and frame < 1210) and 1 or 0)
  set("1 Player Start", (frame >= 1400 and frame < 1410) and 1 or 0)
  if frame > 1000 then mem:write_u8(0x9ab7, 1) end -- keep the tone chip quiet
  if frame > 1600 then
    local ph = (frame // 70) % 4
    set("P1 Left", (ph == 0 or ph == 3) and 1 or 0)
    set("P1 Right", (ph == 1 or ph == 2) and 1 or 0)
    mem:write_u8(0x9820, 3)
  end
  if frame >= total then out:close(); m:exit() end
end
_G.__sub = emu.add_machine_frame_notifier(tick)
