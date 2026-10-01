-- Per-frame sprite load statistics: formation vs flying, movement per frame.
local total = tonumber(os.getenv("GFRAMES") or "150000")
local m = manager.machine
local mem = m.devices[":maincpu"].spaces["program"]
local fields = {}
for _, port in pairs(m.ioport.ports) do
  for name, f in pairs(port.fields) do fields[name] = f end
end
local function set(name, v) local f = fields[name]; if f then f:set_value(v) end end
local rack = fields["Rack Test"]
local frame, stuck_stage, stuck_since = 0, -1, 0
local prev = {}
local V = { fighter = {}, bullet = {}, bomb = {}, enemy = {} }
local H = { nvis = {}, nother = {}, nform = {}, nmoved = {}, status = {}, fdelta = {}, odelta = {}, big = {} }
local peak = { vis = 0, other = 0 }
local function inc(t, k) t[k] = (t[k] or 0) + 1 end

local function tick()
  frame = frame + 1
  local stage = mem:read_u8(0x9821)
  set("Coin 1", (frame >= 1200 and frame < 1210) and 1 or 0)
  set("1 Player Start", (frame >= 1400 and frame < 1410) and 1 or 0)
  if frame > 1600 then
    local ph = (frame // 70) % 4
    set("P1 Left", (ph == 0 or ph == 3) and 1 or 0)
    set("P1 Right", (ph == 1 or ph == 2) and 1 or 0)
    set("P1 Button 1", (frame % 6 < 3) and 1 or 0)
    mem:write_u8(0x9820, 3)
    if stage ~= stuck_stage then stuck_stage = stage; stuck_since = frame end
    local want = (frame - stuck_since > 5400) and 0x00 or 0x20
    if rack.user_value ~= want then rack.user_value = want end
  end
  if frame > 1700 then
    for offs = 0, 0x7e, 2 do
      local tile = mem:read_u8(0x8b80 + offs) & 0x7f
      local color = mem:read_u8(0x8b81 + offs) & 0x3f
      local c0 = mem:read_u8(0x9b80 + offs)
      local c1 = mem:read_u8(0x9b81 + offs)
      local sizex, sizey = (c0 >> 2) & 1, (c0 >> 3) & 1
      local sx = mem:read_u8(0x9381 + offs) - 40 + 0x100 * (c1 & 3)
      local sy = ((256 - mem:read_u8(0x9380 + offs) + 1 - 16 * sizey) & 0xff) - 32
      if sx > -16 * (sizex + 1) and sx < 288 and sy > -16 * (sizey + 1) and sy < 224 then
        local kind = "enemy"
        if tile >= 0x30 and tile <= 0x33 then kind = (color == 9) and "bullet" or "bomb"
        elseif (color == 9 or color == 7) and tile < 8 and mem:read_u8(0x8800 + offs) ~= 1 then kind = "fighter" end
        inc(V[kind], sx)
      end
    end
  end
  if frame == total then
    local out = io.open("vpos.txt", "w")
    for kind, t in pairs(V) do
      local parts = {}
      for x = -31, 287 do if t[x] then parts[#parts + 1] = x .. "=" .. t[x] end end
      out:write(kind .. ": " .. table.concat(parts, " ") .. "\n")
    end
    out:close()
    m:exit()
  end
end
_G.__sub = emu.add_machine_frame_notifier(tick)
