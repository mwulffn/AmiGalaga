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
    local nvis, nform, nother, nmoved, nbig = 0, 0, 0, 0, 0
    local cur = {}
    for offs = 0, 0x7e, 2 do
      local color = mem:read_u8(0x8b81 + offs) & 0x3f
      local c0 = mem:read_u8(0x9b80 + offs)
      local c1 = mem:read_u8(0x9b81 + offs)
      local sizex, sizey = (c0 >> 2) & 1, (c0 >> 3) & 1
      local sx = mem:read_u8(0x9381 + offs) - 40 + 0x100 * (c1 & 3)
      local sy = ((256 - mem:read_u8(0x9380 + offs) + 1 - 16 * sizey) & 0xff) - 32
      if sx > -16 * (sizex + 1) and sx < 288 and sy > -16 * (sizey + 1) and sy < 224
         and color ~= 9 and color ~= 7 then
        local st = mem:read_u8(0x8800 + offs)
        nvis = nvis + 1 + sizex + sizey + sizex * sizey
        if sizex + sizey > 0 then nbig = nbig + 1 end
        inc(H.status, st)
        cur[offs] = { sx, sy }
        local p = prev[offs]
        local key = p and string.format("%d,%d", sy - p[2], sx - p[1]) or "new"
        if st == 1 then
          nform = nform + 1
          inc(H.fdelta, key)
          if key ~= "0,0" then nmoved = nmoved + 1 end
        else
          nother = nother + 1
          if p then
            local d = math.max(math.abs(sx - p[1]), math.abs(sy - p[2]))
            inc(H.odelta, d > 8 and 9 or d)
          end
        end
      end
    end
    prev = cur
    inc(H.nvis, nvis); inc(H.nform, nform); inc(H.nother, nother); inc(H.nmoved, nmoved); inc(H.big, nbig)
    if nvis > peak.vis then peak.vis = nvis; peak.visf = frame; peak.vis_other = nother end
    if nother > peak.other then peak.other = nother; peak.otherf = frame; peak.other_form = nform end
  end
  if frame == total then
    local out = io.open("load.txt", "w")
    out:write(string.format("peak vis=%d (frame %d, other=%d) peak other=%d (frame %d, form=%d)\n",
      peak.vis, peak.visf, peak.vis_other, peak.other, peak.otherf, peak.other_form))
    for name, t in pairs(H) do
      local keys = {}
      for k in pairs(t) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      local parts = {}
      for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. t[k] end
      out:write(name .. ": " .. table.concat(parts, " ") .. "\n")
    end
    out:close()
    m:exit()
  end
end
_G.__sub = emu.add_machine_frame_notifier(tick)
