-- @description Track Builder - Manage Songs and Projects in REAPER
-- @version 1.3
-- @author Victor Veiga
-- @about
--   # Track Builder
--   This script allows you to manage and organize songs inside REAPER.
--   ## Features:
--   - Login authentication system
--   - Browse and select songs from API.
--   - Create new projects.
--   - Download and open projects directly.
--   - Track progress with an interactive UI.
--   - Manage local projects with delete functionality
--   - Save local projects to cloud with RPP file upload
-- @changelog
--   v1.3 - Added Save to Cloud functionality for local projects
--   v1.2 - Added local project management with save/delete functionality
--   v1.1 - Added authentication system with login screen
--   v1.0 - Initial release
-- @provides
--   [main] Scripts/VictorVeiga/TrackBuilder/track_builder.lua
-- @link https://github.com/victorveiga/reaper-track-builder
-- @screenshot https://raw.githubusercontent.com/victorveiga/reaper-track-builder/main/Screenshots/track_builder.png

-- Adjust Lua search path
local scriptPath = reaper.GetResourcePath() .. "/Scripts/Track Builder Scripts/Scripts"
package.path = package.path .. ";" .. scriptPath .. "/?.lua"

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

-- Import modules
local auth = require "auth"
local api = require "api"
local ui = require "ui"
local projects = require "projects"
local downloads = require "downloads"
local uploads = require "uploads"
local utils = require "utils"

-- Import ReaImGui
local ctx = reaper.ImGui_CreateContext('Song Selector')

-- State variables
local state = {
    songs = {},
    filteredSongs = {},
    selectedSongs = {},
    windowOpen = true,
    currentPage = 1,
    songsPerPage = 10,
    loadedSongs = false,
    searchQuery = "",
    projectName = "",
    eventDate = "",
    orderedSongs = {},
    userId = "4aaca8b3-a6b7-4100-9080-5b761948682c",
    activeScreen = "login",
    projects = {},
    loadedProjects = false,
    currentProjectPage = 1,
    projectsPerPage = 10,
    localProjects = {},
    loadedLocalProjects = false,
    keys = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"},
    songKeys = {},
    needsReorder = false,
    moveFrom = -1,
    moveTo = -1
}

-- Initialize modules with context and state
auth.init(ctx, state)
api.init(auth)
ui.init(ctx, state, auth, api, projects, downloads, uploads, utils)
projects.init(ctx, state, auth, api, utils)
downloads.init(ctx, state, utils)
uploads.init(ctx, state, auth, api, utils)

function drawUI()
    if not state.windowOpen then return end
    
    -- Try to load saved token on first run
    if state.activeScreen == "login" and not auth.isAuthenticated() then
        local savedToken = auth.loadToken()
        if savedToken and savedToken ~= "" then
            auth.setToken(savedToken)
            -- Load data after token validation
            reloadDataAfterLogin()
            state.activeScreen = "menu"
        end
    end
    
    -- Force refresh if we need to load data but are authenticated
    if auth.isAuthenticated() and state.activeScreen ~= "login" and state.activeScreen ~= "download_progress" and state.activeScreen ~= "upload_progress" then
        if not state.loadedSongs then
            state.songs = api.getSongs() or {}
            state.filteredSongs = state.songs
            state.loadedSongs = true
        end
        
        if not state.loadedProjects then
            state.projects = api.getProjects() or {}
            state.loadedProjects = true
        end
        
        -- Load local projects when authenticated
        if not state.loadedLocalProjects then
            projects.loadLocalProjects()
            state.loadedLocalProjects = true
        end
    end
    
    ui.draw()
end

function reloadDataAfterLogin()
    -- Reset states to force reload
    state.loadedSongs = false
    state.loadedProjects = false
    state.loadedLocalProjects = false
    
    -- Load songs
    state.songs = api.getSongs() or {}
    state.filteredSongs = state.songs
    state.loadedSongs = true
    
    -- Load projects
    state.projects = api.getProjects() or {}
    state.loadedProjects = true
    
    -- Load local projects
    projects.loadLocalProjects()
    state.loadedLocalProjects = true
end

function loop()
    drawUI()
    if state.windowOpen then
        r.defer(loop)
    end
end

r.defer(loop)