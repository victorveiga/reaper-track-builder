local projects = {}
local json = require "dkjson"
local r = reaper

-- Module dependencies
local ctx
local state
local auth
local api
local utils

function projects.init(context, globalState, authModule, apiModule, utilsModule)
    ctx = context
    state = globalState
    auth = authModule
    api = apiModule
    utils = utilsModule
end

function projects.getLocalProjectsFilePath()
    return reaper.GetResourcePath() .. "/Scripts/Track Builder Scripts/.local_projects"
end

function projects.saveLocalProjects()
    local filePath = projects.getLocalProjectsFilePath()
    local file = io.open(filePath, "w")
    if file then
        local data = json.encode(state.localProjects)
        file:write(data)
        file:close()
    end
end

function projects.loadLocalProjects()
    local filePath = projects.getLocalProjectsFilePath()
    local file = io.open(filePath, "r")
    if file then
        local content = file:read("*a")
        file:close()
        local data = json.decode(content)
        if data then
            state.localProjects = data
        end
    end
end

function projects.addLocalProject(projectId, projectName, projectPath)
    -- Check if project already exists
    for _, project in ipairs(state.localProjects) do
        if project.id == projectId then
            return
        end
    end
    
    -- Add new project
    table.insert(state.localProjects, {
        id = projectId,
        name = projectName,
        path = projectPath,
        downloadedAt = os.date("%Y-%m-%d %H:%M:%S")
    })
    
    projects.saveLocalProjects()
end

function projects.removeLocalProject(projectId)
    for i, project in ipairs(state.localProjects) do
        if project.id == projectId then
            table.remove(state.localProjects, i)
            projects.saveLocalProjects()
            return true
        end
    end
    return false
end

function projects.deleteLocalProject(projectId)
    -- Find project
    local projectToDelete = nil
    for _, project in ipairs(state.localProjects) do
        if project.id == projectId then
            projectToDelete = project
            break
        end
    end
    
    if projectToDelete then
        -- Delete the project folder
        local tempPath = reaper.GetResourcePath() .. "/Temp/" .. projectId
        local deleteCommand
        local osName = utils.getOS()
        
        if osName:match("Win") then
            deleteCommand = string.format('rd /s /q "%s"', tempPath)
        else
            deleteCommand = string.format('rm -rf "%s"', tempPath)
        end
        
        os.execute(deleteCommand)
        
        -- Remove from local projects list
        projects.removeLocalProject(projectId)
        
        return true
    end
    
    return false
end

function projects.createProject()
    local projectData = {
        name = state.projectName,
        songs = {},
        user_id = state.userId
    }
    
    for i, song in ipairs(state.orderedSongs) do
        table.insert(projectData.songs, {
            key = state.songKeys[song.id],
            original_key = song.key,
            song_id = song.id,
            position = i
        })
    end
    
    local responseData = api.createProject(projectData)
    
    if responseData and responseData.zip_file then
        local result = r.ShowMessageBox("Project created successfully! Would you like to open it now?", "Success", 4)
        if result == 6 then
            local downloads = require "downloads"
            downloads.openProject(responseData.id, responseData.zip_file, responseData.static_files, state.projectName)
        else
            state.windowOpen = false
        end
    else
        r.ShowMessageBox("Project created but no file was returned.", "Warning", 0)
        state.windowOpen = false
    end
end

function projects.openLocalProject(projectPath)
    reaper.Main_openProject(projectPath)
    state.windowOpen = false
end

return projects