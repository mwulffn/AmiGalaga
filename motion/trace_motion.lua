-- Dump the motion queue and everything the stepper reads, once per frame.
local total = tonumber(os.getenv("GFRAMES") or "40000")
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local fields = {}
for _, port in pairs(m.ioport.ports) do
  for name, f in pairs(port.fields) do fields[name] = f end
end
local function set(name, v) local f = fields[name]; if f then f:set_value(v) end end
local out = io.open(os.getenv("GOUT") or "motion.bin", "wb")
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
  if frame > 1390 then
    out:write(mem:read_range(0x92a0, 0x92a0, 8), mem:read_range(0x9100, 0x91ef, 8),
      mem:read_range(0x8800, 0x887f, 8), mem:read_range(0x9800, 0x981f, 8),
      mem:read_range(0x9900, 0x991f, 8), mem:read_range(0x99c0, 0x99ca, 8),
      string.char(mem:read_u8(0x9362), mem:read_u8(0x93e2), mem:read_u8(0x9215),
        mem:read_u8(0x92aa), mem:read_u8(0x901d), mem:read_u8(0x92e2), mem:read_u8(0x92c8),
        mem:read_u8(0x9821)))
  end
  if frame >= total then out:close(); m:exit() end
end
_G.__sub = emu.add_machine_frame_notifier(tick)
