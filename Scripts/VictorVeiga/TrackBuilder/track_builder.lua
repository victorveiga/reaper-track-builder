-- @description Track Builder - Manage Songs and Projects in REAPER
-- @version 1.0
-- @author Victor Veiga
-- @about
--   # Track Builder
--   This script allows you to manage and organize songs inside REAPER.
--   ## Features:
--   - Browse and select songs from API.
--   - Create new projects.
--   - Download and open projects directly.
--   - Track progress with an interactive UI.
-- @changelog
--   v1.0 - Initial release
-- @provides
--   [main] Scripts/VictorVeiga/TrackBuilder/track_builder.lua
-- @link https://github.com/victorveiga/reaper-track-builder
-- @screenshot https://raw.githubusercontent.com/victorveiga/reaper-track-builder/main/Screenshots/track_builder.png

-- Adjust Lua search path
local scriptPath = reaper.GetResourcePath() .. "/Scripts/Track Builder Scripts/Scripts"
package.path = package.path .. ";" .. scriptPath .. "/?.lua"

-- REAPER Script to list songs from the API with graphical interface
-- Requires ReaImGui

local r = reaper

-- Check if ReaImGui is installed
if not reaper.APIExists("ImGui_CreateContext") then
    reaper.ShowMessageBox(
        "This script requires ReaImGui. Please install it via ReaPack.",
        "ReaImGui not found",
        0
    )
    return
end

-- Import ReaImGui
local ctx = reaper.ImGui_CreateContext('Song Selector')
local json = require "dkjson"
local songsUrl = "https://7yfzvu0rj5.execute-api.eu-west-3.amazonaws.com/songs"
local projectsUrl = "https://7yfzvu0rj5.execute-api.eu-west-3.amazonaws.com/projects?user_id=4aaca8b3-a6b7-4100-9080-5b761948682c"
local projectCreateUrl = "https://7yfzvu0rj5.execute-api.eu-west-3.amazonaws.com/projects"

-- ImGui Flags
local ImGui_WindowFlags_None = 0
local ImGui_ChildFlags_Border = 1
local ImGui_DragDropFlags_None = 0
local ImGui_ComboFlags_None = 0
local ImGui_SelectableFlags_None = 0

-- State variables
local songs = {}
local filteredSongs = {}
local selectedSongs = {}
local windowOpen = true
local currentPage = 1
local songsPerPage = 10
local loadedSongs = false
local searchQuery = ""
local projectName = ""
local eventDate = ""
local orderedSongs = {}
local userId = "4aaca8b3-a6b7-4100-9080-5b761948682c"
local activeScreen = "menu"
local downloadState = {
    isDownloading = false,
    currentFile = "",
    totalFiles = 0,
    completedFiles = 0,
    projectToOpen = nil,
    currentOperation = "downloading",
    extractionProgress = 0
}
local osName = reaper.GetOS()

local keys = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local songKeys = {}  -- Store selected keys for each song
local needsReorder = false
local moveFrom = -1
local moveTo = -1

-- Colors and styles
local colors = {
    button = 0x6495ED,         -- Cornflower blue
    buttonHovered = 0x4169E1,  -- Royal blue
    background = 0x2F4F4F,     -- Dark slate gray
    text = 0xFFFFFF,          -- White
    checkbox = 0x98FB98       -- Pale green
}

function getSongs()
    local command = "curl -s " .. songsUrl
    local handle = io.popen(command)
    local response = handle:read("*a")
    handle:close()
    
    if response == "" then
        r.ShowMessageBox("Could not connect to the API. Check your connection.", "Error", 0)
        return nil
    end
    
    local data, _, err = json.decode(response)
    if err then
        r.ShowMessageBox("Error loading songs: " .. err, "Error", 0)
        return nil
    end
    
    return data.items
end

function reorderSongs()
    if moveFrom > 0 and moveTo > 0 and moveFrom ~= moveTo then
        local temp = table.remove(orderedSongs, moveFrom)
        table.insert(orderedSongs, moveTo, temp)
        
        -- Reset the move indicators
        moveFrom = -1
        moveTo = -1
        needsReorder = false
    end
end

function createProject()
    local projectData = {
        name = projectName,
        songs = {},
        user_id = userId
    }
    
    for i, song in ipairs(orderedSongs) do
        table.insert(projectData.songs, {
            key = songKeys[song.id],
            original_key = song.key,
            song_id = song.id,
            position = i
        })
    end
    
    local jsonData = json.encode(projectData)
    
    local tempPath = reaper.GetResourcePath() .. "/Temp"
    local tempFile = tempPath .. "/project_data.json"
    
    if osName:match("Win") then
        os.execute('if not exist "' .. tempPath .. '" mkdir "' .. tempPath .. '"')
    else
        os.execute('mkdir -p "' .. tempPath .. '"')
    end
    
    local file = io.open(tempFile, "w")
    file:write(jsonData)
    file:close()
    
    local command = string.format('curl -s -X POST -H "Content-Type: application/json" -d @"%s" %s', tempFile, projectCreateUrl)
    
    local handle = io.popen(command)
    local response = handle:read("*a")
    handle:close()
    
    local responseData = json.decode(response)

    os.remove(tempFile)
    
    if responseData and responseData.zip_file then
        local result = r.ShowMessageBox("Project created successfully! Would you like to open it now?", "Success", 4)
        -- Result 6 means "Yes" was clicked, 7 means "No"
        if result == 6 then
            openProject(responseData.id, responseData.zip_file, responseData.static_files)
        else
            windowOpen = false
        end
    else
        r.ShowMessageBox("Project created but no file was returned.", "Warning", 0)
        windowOpen = false
    end
end

function filterSongs()
    filteredSongs = {}
    if searchQuery == "" then
        filteredSongs = songs
    else
        for _, song in ipairs(songs) do
            if string.find(string.lower(song.title), string.lower(searchQuery)) or 
               string.find(string.lower(song.artist), string.lower(searchQuery)) then
                table.insert(filteredSongs, song)
            end
        end
    end
end

function findKeyIndex(key)
    for i, k in ipairs(keys) do
        if k == key then
            return i - 1
        end
    end
    return 0
end

function initializeSongKeys()
    for _, song in ipairs(orderedSongs) do
        if not songKeys[song.id] then
            songKeys[song.id] = song.key or "C"
        end
    end
end

function reorderSongs()
    if moveFrom > 0 and moveTo > 0 and moveFrom ~= moveTo then
        local temp = table.remove(orderedSongs, moveFrom)
        table.insert(orderedSongs, moveTo, temp)
        moveFrom = -1
        moveTo = -1
        needsReorder = false
    end
end

function getProjects()
    local command = "curl -s " .. projectsUrl
    local handle = io.popen(command)
    local response = handle:read("*a")
    handle:close()
    
    if response == "" then
        r.ShowMessageBox("Could not connect to the API. Check your connection.", "Error", 0)
        return nil
    end
    
    local data, _, err = json.decode(response)
    if err then
        r.ShowMessageBox("Error loading projects: " .. err, "Error", 0)
        return nil
    end
    
    return data.items
end

function startDownload(projectId, projectUrl, staticFiles)
    downloadState = {
        isDownloading = true,
        currentFile = "project.rpp",
        totalFiles = staticFiles and #staticFiles + 1 or 1,
        completedFiles = 0,
        currentOperation = "downloading",
        extractionProgress = 0,
        projectToOpen = {
            id = projectId,
            url = projectUrl,
            staticFiles = staticFiles,
            tempDir = reaper.GetResourcePath() .. "/Temp/" .. projectId,
            downloadQueue = {},
            extractQueue = {}
        }
    }
    
    os.execute("mkdir \"" .. downloadState.projectToOpen.tempDir .. "\"")
    
    -- Always download project.rpp (no check for existence)
    table.insert(downloadState.projectToOpen.downloadQueue, {
        url = projectUrl,
        path = downloadState.projectToOpen.tempDir .. "/project.rpp",
        isZip = false
    })
    
    if staticFiles then
        for _, fileUrl in ipairs(staticFiles) do
            local fileName = fileUrl:match(".*/(.-)$")
            if fileName then
                local isZip = fileName:match("%.zip$") ~= nil
                local filePath = downloadState.projectToOpen.tempDir .. "/" .. fileName
                
                -- For zip files, check if the extracted directory exists
                local skipDownload = false
                if isZip then
                    local extractedDirName = fileName:gsub("%.zip$", "")
                    local extractedPath = downloadState.projectToOpen.tempDir .. "/" .. extractedDirName
                    if reaper.file_exists(extractedPath) then
                        skipDownload = true
                        downloadState.completedFiles = downloadState.completedFiles + 1
                    end
                else
                    -- For non-zip files, check if the file exists
                    if reaper.file_exists(filePath) then
                        skipDownload = true
                        downloadState.completedFiles = downloadState.completedFiles + 1
                    end
                end
                
                if not skipDownload then
                    table.insert(downloadState.projectToOpen.downloadQueue, {
                        url = fileUrl,
                        path = filePath,
                        isZip = isZip
                    })
                end
                
                if isZip and not skipDownload then
                    table.insert(downloadState.projectToOpen.extractQueue, {
                        zipPath = filePath,
                        extractDir = downloadState.projectToOpen.tempDir
                    })
                end
            end
        end
    end
end

function extractZipFiles()
    if #downloadState.projectToOpen.extractQueue > 0 then
        downloadState.currentOperation = "extracting"
        local current = table.remove(downloadState.projectToOpen.extractQueue, 1)
        
        downloadState.currentFile = "Extracting " .. current.zipPath:match("([^/\\]+)%.zip$")
        
        local command
        if osName:match("Win") then
            command = string.format('powershell -Command "Expand-Archive -Force -Path \'%s\' -DestinationPath \'%s\'" > NUL 2>&1', current.zipPath, current.extractDir)            
        else
            command = string.format('unzip -o "%s" -d "%s"', current.zipPath, current.extractDir)
        end
        os.execute(command)
        
        os.remove(current.zipPath)
        
        downloadState.extractionProgress = downloadState.extractionProgress + 1
        
        if #downloadState.projectToOpen.extractQueue > 0 then
            reaper.defer(extractZipFiles)
        else
            local projectPath = downloadState.projectToOpen.tempDir .. "/project.rpp"
            reaper.Main_openProject(projectPath)
            downloadState.isDownloading = false
            windowOpen = false
        end
    end
end

function processDownload()
    if not downloadState.isDownloading then return end
    
    local current = downloadState.projectToOpen.downloadQueue[1]
    if current then
        -- If it's project.rpp or file doesn't exist, download it
        if current.path:match("project%.rpp$") or not reaper.file_exists(current.path) then
            local command = string.format("curl -s -o \"%s\" \"%s\"", current.path, current.url)
            os.execute(command)
        end
        
        downloadState.completedFiles = downloadState.completedFiles + 1
        if downloadState.projectToOpen.downloadQueue[2] then
            downloadState.currentFile = downloadState.projectToOpen.downloadQueue[2].url:match(".*/(.-)$") or ""
        end
        table.remove(downloadState.projectToOpen.downloadQueue, 1)
        
        reaper.defer(processDownload)
    else
        if #downloadState.projectToOpen.extractQueue > 0 then
            reaper.defer(extractZipFiles)
        else
            local projectPath = downloadState.projectToOpen.tempDir .. "/project.rpp"
            reaper.Main_openProject(projectPath)
            downloadState.isDownloading = false
            windowOpen = false
        end
    end
end

-- Add helper function to check if file exists
if not reaper.file_exists then
    function reaper.file_exists(path)
        local f = io.open(path, "r")
        if f then
            f:close()
            return true
        end
        return false
    end
end


function openProject(projectId, projectUrl, staticFiles)
    if projectUrl and projectUrl ~= "" then
        activeScreen = "download_progress"
        startDownload(projectId, projectUrl, staticFiles)
        reaper.defer(processDownload)
    else
        reaper.ShowMessageBox("No project file available.", "Error", 0)
    end
end


function drawSelectionScreen()
    r.ImGui_Text(ctx, 'Select Songs')
    r.ImGui_Separator(ctx)

    changed, searchQuery = r.ImGui_InputText(ctx, "Search", searchQuery, 256)
    if changed then
        filterSongs()
    end

    r.ImGui_Separator(ctx)

    local startIdx = ((currentPage - 1) * songsPerPage) + 1
    local endIdx = math.min(startIdx + songsPerPage - 1, #filteredSongs)

    if r.ImGui_BeginChild(ctx, 'SongList', 0, 280, ImGui_ChildFlags_Border) then
        for i = startIdx, endIdx do
            local song = filteredSongs[i]
            if song then
                local isSelected = selectedSongs[song.id] or false
                local changed, checked = r.ImGui_Checkbox(ctx, song.title, isSelected)
                if changed then
                    selectedSongs[song.id] = checked
                end
            end
        end
        r.ImGui_EndChild(ctx)
    end

    r.ImGui_Separator(ctx)

    local totalPages = math.ceil(#filteredSongs / songsPerPage)
    r.ImGui_Text(ctx, string.format("Page %d of %d", currentPage, totalPages))    

    if currentPage > 1 then
        if r.ImGui_Button(ctx, 'Previous') then
            currentPage = currentPage - 1
        end
        r.ImGui_SameLine(ctx)
    end

    if currentPage < totalPages then
        if r.ImGui_Button(ctx, 'Next') then
            currentPage = currentPage + 1
        end
        r.ImGui_SameLine(ctx)
    end

    if r.ImGui_Button(ctx, 'Confirm Selection') then
        orderedSongs = {}
        for songId, selected in pairs(selectedSongs) do
            if selected then
                for _, song in ipairs(songs) do
                    if song.id == songId then
                        table.insert(orderedSongs, song)
                        break
                    end
                end
            end
        end
        activeScreen = "create_projects"
    end

    if r.ImGui_Button(ctx, 'Back') then
        activeScreen = "menu"
    end
end


function drawProjectScreen()
    if #orderedSongs > 0 and not next(songKeys) then
        initializeSongKeys()
    end

    if needsReorder then
        reorderSongs()
    end

    r.ImGui_Text(ctx, 'Create New Project')
    r.ImGui_Separator(ctx)
    
    _, projectName = r.ImGui_InputText(ctx, "Project Name", projectName, 256)
    _, eventDate = r.ImGui_InputText(ctx, "Event Date", eventDate, 256)
    
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, 'Arrange Songs and Select Keys')
    
    local comboWidth = 80
    
    if r.ImGui_BeginChild(ctx, 'OrderedSongs', 0, 200, ImGui_ChildFlags_Border) then
        for i, song in ipairs(orderedSongs) do
            r.ImGui_PushID(ctx, i)
            
            r.ImGui_BeginGroup(ctx)
            
            local selectableWidth = 280
            local isSelected = false
            if r.ImGui_Selectable(ctx, string.format("%d. %s", i, song.title), isSelected, 0, selectableWidth, 20) then
                isSelected = true
            end
            
            if r.ImGui_BeginDragDropSource(ctx, ImGui_DragDropFlags_None) then
                moveFrom = i
                r.ImGui_SetDragDropPayload(ctx, 'SONG_REORDER', tostring(i))
                r.ImGui_Text(ctx, "Moving: " .. song.title)
                r.ImGui_EndDragDropSource(ctx)
            end
            
            if r.ImGui_BeginDragDropTarget(ctx) then
                local payload = r.ImGui_AcceptDragDropPayload(ctx, 'SONG_REORDER')
                if payload then
                    moveTo = i
                    needsReorder = true
                end
                r.ImGui_EndDragDropTarget(ctx)
            end
            
            r.ImGui_SameLine(ctx, 300)
            
            local currentKey = songKeys[song.id] or song.key or "C"
            local currentKeyIndex = findKeyIndex(currentKey)
            
            r.ImGui_SetNextItemWidth(ctx, comboWidth)
            local changed, newIndex = r.ImGui_Combo(ctx, "##key" .. i, currentKeyIndex, table.concat(keys, "\0") .. "\0")
            if changed then
                songKeys[song.id] = keys[newIndex + 1]
            end
            
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, string.format("(Original: %s)", song.key or "?"))
            
            r.ImGui_EndGroup(ctx)
            r.ImGui_PopID(ctx)
            
            if i < #orderedSongs then
                r.ImGui_Separator(ctx)
            end
        end
        r.ImGui_EndChild(ctx)
    end
    
    r.ImGui_Separator(ctx)

    if r.ImGui_Button(ctx, 'Create Project') then
        createProject()
    end
    
    r.ImGui_SameLine(ctx)
    
    if r.ImGui_Button(ctx, 'Back') then
        activeScreen = "songs"
    end
end

function drawProjectsList()
    r.ImGui_Text(ctx, 'Your Projects')
    
    r.ImGui_Separator(ctx)
    
    if r.ImGui_BeginChild(ctx, 'ProjectList', 0, 280, ImGui_ChildFlags_Border) then
        for _, project in ipairs(projects) do
            r.ImGui_Text(ctx, "Project: " .. project.name)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Open##" .. project.id) then
                openProject(project.id, project.zip_file, project.static_files)
            end
        end
        r.ImGui_EndChild(ctx)
    end
    
    r.ImGui_Separator(ctx)
    
    if r.ImGui_Button(ctx, 'Back') then
        activeScreen = "menu"
    end
end

function drawMenu()
    r.ImGui_Text(ctx, 'Main Menu')
    r.ImGui_Separator(ctx)
    
    if r.ImGui_Button(ctx, 'List Songs') then
        activeScreen = "songs"
    end
    
    if r.ImGui_Button(ctx, 'List Projects') then
        activeScreen = "projects"
    end
    
    if r.ImGui_Button(ctx, 'Exit') then
        windowOpen = false
    end
end

function drawDownloadProgressScreen()
    r.ImGui_Text(ctx, 'Project Download Progress')
    r.ImGui_Separator(ctx)
    
    if downloadState.currentOperation == "downloading" then
        local progress = downloadState.completedFiles / downloadState.totalFiles
        r.ImGui_ProgressBar(ctx, progress, -1, 0, string.format("%d/%d files", downloadState.completedFiles, downloadState.totalFiles))
        r.ImGui_Text(ctx, "Downloading: " .. downloadState.currentFile)
    else
        local totalExtractions = #downloadState.projectToOpen.extractQueue + downloadState.extractionProgress
        local progress = downloadState.extractionProgress / totalExtractions
        r.ImGui_ProgressBar(ctx, progress, -1, 0, string.format("%d/%d files extracted", downloadState.extractionProgress, totalExtractions))
        r.ImGui_Text(ctx, downloadState.currentFile)
    end
    
    if r.ImGui_Button(ctx, 'Cancel') then
        downloadState.isDownloading = false
        activeScreen = "projects"
    end
end


function drawUI()
    if not windowOpen then return end
    
    if not loadedSongs then
        songs = getSongs() or {}
        filteredSongs = songs
        loadedSongs = true
    end
    
    if not loadedProjects then
        projects = getProjects() or {}
        loadedProjects = true
    end
    
    r.ImGui_SetNextWindowSize(ctx, 600, 600, r.ImGui_Cond_FirstUseEver())
    
    local visible, open = r.ImGui_Begin(ctx, 'Project Manager', true, ImGui_WindowFlags_None)
    windowOpen = open
    
    if visible then
        if activeScreen == "menu" then
            drawMenu()
        elseif activeScreen == "songs" then
            drawSelectionScreen()
        elseif activeScreen == "projects" then
            drawProjectsList()
        elseif activeScreen == "create_projects" then
            drawProjectScreen()
        elseif activeScreen == "download_progress" then
            drawDownloadProgressScreen()
        end
        r.ImGui_End(ctx)
    end
end

function loop()
    drawUI()
    if windowOpen then
        r.defer(loop)
    end
end

r.defer(loop)
