local decoder      = require("cc.audio.dfpwm").make_decoder()

-- === CONFIGURATION ===
local serverIP     = "cc-void-city-radio-piueq.ondigitalocean.app"
local wsUrl        = "wss://" .. serverIP .. "/ws"
local MAX_VOLUME   = 3.0
local SLIDER_WIDTH = 20
local VOLUME_STEP  = MAX_VOLUME / SLIDER_WIDTH
local volume       = MAX_VOLUME

-- === AUTO-UPDATE VIA GITHUB RELEASES ===
local VERSION      = "1.0.0"
local GITHUB_OWNER = "Coop25"       -- ← change from "<USER>"
local GITHUB_REPO  = "cc-Radio-Lua" -- ← change from "<REPO>"
local RELEASE_API  = string.format(
    "https://api.github.com/repos/%s/%s/releases/latest",
    GITHUB_OWNER, GITHUB_REPO
)
local RAW_BASE     = string.format(
    "https://raw.githubusercontent.com/%s/%s/main/",
    GITHUB_OWNER, GITHUB_REPO
)

local function tryGitHubUpdate()
    if not http or not fs or not textutils then return end
    -- fetch latest release metadata
    local resp = http.get(RELEASE_API)
    if not resp then return end
    local data = textutils.unserializeJSON(resp.readAll())
    resp.close()
    local remoteTag = data.tag_name
    if not remoteTag or remoteTag == VERSION then return end
    -- find asset named "computercraft_radio.lua" in release assets
    local downloadUrl
    for _, asset in ipairs(data.assets) do
        if asset.name == "startup.lua" then
            downloadUrl = asset.browser_download_url
            break
        end
    end
    if not downloadUrl then return end
    -- download and overwrite
    local scriptResp = http.get(downloadUrl)
    if not scriptResp then return end
    local code = scriptResp.readAll()
    scriptResp.close()
    local prog = shell.getRunningProgram()
    local f = fs.open(prog, "w")
    f.write(code)
    f.close()
    -- restart
    shell.run(prog)
end

-- attempt update before anything else
tryGitHubUpdate()

-- detect Advanced Computer (built-in color touchscreen)
local isAdvanced = term.isColor()

-- detect Turtle and set its label
local isTurtle = type(turtle) == "table" and turtle.getLabel
if isTurtle then
    -- label includes version for easy identification
    pcall(turtle.setLabel, "VoidCity Radio")
end

-- find speaker peripheral
local speakers = { peripheral.find("speaker") }
if #speakers == 0 then
    error("No speaker attached; please hook up a speaker peripheral.")
end

-- draw the volume slider on line 1\
local function drawSlider(vol)
    term.setCursorPos(1, 1)
    term.clearLine()
    local pct    = vol / MAX_VOLUME
    local filled = math.floor(pct * SLIDER_WIDTH + 0.5)
    if isAdvanced then
        term.setBackgroundColor(colors.white)
        term.write(string.rep(" ", filled))
        term.setBackgroundColor(colors.gray)
        term.write(string.rep(" ", SLIDER_WIDTH - filled))
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.write(" " .. math.floor(pct * 100) .. "%")
        term.setTextColor(colors.white)
    else
        local rail = "|" .. string.rep("-", SLIDER_WIDTH) .. "|"
        local chars = {}
        for i = 1, #rail do chars[i] = rail:sub(i, i) end
        chars[filled + 1] = "O"
        term.write(table.concat(chars) .. " " .. math.floor(pct * 100) .. "%")
    end
end

-- draw current song info on line 5
local function drawSongInfo(name, artist)
    term.setCursorPos(1, 4)
    term.clearLine()
    term.write("Now Playing: " .. (name or "?") .. " - " .. (artist or "?"))
end

-- playback coroutine
local function playbackLoop()
    while true do
        term.clear()
        drawSlider(volume)
        term.setCursorPos(1, 3)
        term.clearLine()
        print("Connecting…")

        local ws = http.websocket(wsUrl)
        if not ws then
            print("Connection failed, retrying in 5s…")
            os.sleep(5)
        else
            term.setCursorPos(1, 3)
            term.clearLine()
            print("Connected")

            -- stream loop
            while true do
                local msg = ws.receive()
                if not msg then
                    print("Stream lost, reconnecting in 2s…")
                    os.sleep(2)
                    break
                end

                if type(msg) == "string" and msg:sub(1, 1) == "{" then
                    -- JSON packet
                    local ok, data = pcall(textutils.unserializeJSON, msg)
                    if ok and data and data.Type == "songChange" then
                        drawSongInfo(data.Name, data.Artist)
                        -- flush any playing audio
                        for _, sp in ipairs(speakers) do sp.stop() end
                    end
                else
                    -- DFPWM audio chunk
                    local pcm = decoder(msg)
                    for _, sp in ipairs(speakers) do
                        sp.playAudio(pcm, volume)
                        local speakerName = peripheral.getName(sp)
                        repeat
                            local ev, sid = os.pullEvent("speaker_audio_empty")
                        until sid == speakerName
                    end
                end

                os.sleep(0)
            end
        end
    end
end
-- slider-input coroutine
local function sliderLoop()
    drawSlider(volume)
    while true do
        local ev = { os.pullEvent() }
        if isAdvanced and ev[1] == "mouse_click" and ev[4] == 1 then
            local x = ev[3]
            volume = math.min(MAX_VOLUME,
                math.max(0, (x - 1) / (SLIDER_WIDTH - 1) * MAX_VOLUME))
            drawSlider(volume)
        elseif not isAdvanced and ev[1] == "key" then
            local key = ev[2]
            if key == 203 then
                volume = math.max(0, volume - VOLUME_STEP)
                drawSlider(volume)
            elseif key == 205 then
                volume = math.min(MAX_VOLUME, volume + VOLUME_STEP)
                drawSlider(volume)
            end
        end
    end
end

-- main runner with error handling
local function main()
    parallel.waitForAll(playbackLoop, sliderLoop)
end

while true do
    local ok, err = pcall(main)
    if not ok then
        -- allow Ctrl+T termination to stop the program and clear screen
        if tostring(err):find("Terminated") then
            term.setCursorPos(1, 1)
            term.clear()
            return
        end
        -- restart on other errors
        shell.run(prog)
        return
    end
end
