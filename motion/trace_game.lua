-- Dump the main CPU's working memory once per frame, for modelling the game
-- logic: who dives when, timers, object states, sprite RAM.
--   GOUT=game.bin GFRAMES=40000 mame galaga -rompath ../original -video none \
--       -sound none -nothrottle -skip_gameinfo -autoboot_script trace_game.lua
-- GFIRE=0 keeps the bot from shooting, so the formation stays whole.
-- A record is the regions below, in order (see REGIONS in game_trace.py).
local total = tonumber(os.getenv("GFRAMES") or "40000")
local fire = os.getenv("GFIRE") ~= "0"
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local fields = {}
for _, port in pairs(m.ioport.ports) do
  for name, f in pairs(port.fields) do fields[name] = f end
end
local function set(name, v) local f = fields[name]; if f then f:set_value(v) end end
local out = io.open(os.getenv("GOUT") or "game.bin", "wb")
local regions = {
  {0x9200, 0x92ff}, {0x9100, 0x91ef}, {0x8800, 0x887f}, {0x9800, 0x985f}, {0x9900, 0x991f},
  {0x99c0, 0x99cf}, {0x9000, 0x903f}, {0x9300, 0x937f}, {0x9b00, 0x9b7f}, {0x8b00, 0x8b7f},
}
local frame = 0
local function tick()
  frame = frame + 1
  set("Coin 1", (frame >= 1200 and frame < 1210) and 1 or 0)
  set("1 Player Start", (frame >= 1400 and frame < 1410) and 1 or 0)
  if frame > 1600 then
    local ph = (frame // 70) % 4
    set("P1 Left", (ph == 0 or ph == 3) and 1 or 0)
    set("P1 Right", (ph == 1 or ph == 2) and 1 or 0)
    set("P1 Button 1", (fire and frame % 6 < 3) and 1 or 0)
    mem:write_u8(0x9820, 3)
  end
  if frame > 1390 then
    for _, r in ipairs(regions) do out:write(mem:read_range(r[1], r[2], 8)) end
  end
  if frame >= total then out:close(); m:exit() end
end
_G.__sub = emu.add_machine_frame_notifier(tick)
