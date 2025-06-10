local downloads = {}
local r = reaper

-- Module dependencies
local ctx
local state
local utils
local downloadState = {
    isDownloading = false,
    currentFile = "",
    totalFiles = 0,
    completedFiles = 0,
    projectToOpen = nil,
    currentOperation = "downloading",
    extractionProgress = 0
}

function downloads.init(context, globalState, utilsModule)
    ctx = context
    state = globalState
    utils = utilsModule
end

function downloads.getState()
    return downloadState
end

function downloads.startDownload(projectId, projectUrl, staticFiles, projectName)
    downloadState = {
        isDownloading = true,
        currentFile = "project.rpp",
        totalFiles = staticFiles and #staticFiles + 1 or 1,
        completedFiles = 0,
        currentOperation = "downloading",
        extractionProgress = 0,
        projectName = projectName,
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
                    if utils.fileExists(extractedPath) then
                        skipDownload = true
                        downloadState.completedFiles = downloadState.completedFiles + 1
                    end
                else
                    -- For non-zip files, check if the file exists
                    if utils.fileExists(filePath) then
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

function downloads.extractZipFiles()
    if #downloadState.projectToOpen.extractQueue > 0 then
        downloadState.currentOperation = "extracting"
        local current = table.remove(downloadState.projectToOpen.extractQueue, 1)
        
        downloadState.currentFile = "Extracting " .. current.zipPath:match("([^/\\]+)%.zip$")
        
        local command
        local osName = utils.getOS()
        if osName:match("Win") then
            command = string.format('powershell -Command "Expand-Archive -Force -Path \'%s\' -DestinationPath \'%s\'" > NUL 2>&1', current.zipPath, current.extractDir)            
        else
            command = string.format('unzip -o "%s" -d "%s"', current.zipPath, current.extractDir)
        end
        os.execute(command)
        
        os.remove(current.zipPath)
        
        downloadState.extractionProgress = downloadState.extractionProgress + 1
        
        if #downloadState.projectToOpen.extractQueue > 0 then
            reaper.defer(downloads.extractZipFiles)
        else
            local projectPath = downloadState.projectToOpen.tempDir .. "/project.rpp"
            
            -- Add to local projects
            local projects = require "projects"
            projects.addLocalProject(downloadState.projectToOpen.id, downloadState.projectName, projectPath)
            
            reaper.Main_openProject(projectPath)
            downloadState.isDownloading = false
            state.windowOpen = false
        end
    end
end

function downloads.processDownload()
    if not downloadState.isDownloading then return end
    
    local current = downloadState.projectToOpen.downloadQueue[1]
    if current then
        -- If it's project.rpp or file doesn't exist, download it
        if current.path:match("project%.rpp$") or not utils.fileExists(current.path) then
            local command = string.format("curl -s -o \"%s\" \"%s\"", current.path, current.url)
            os.execute(command)
        end
        
        downloadState.completedFiles = downloadState.completedFiles + 1
        if downloadState.projectToOpen.downloadQueue[2] then
            downloadState.currentFile = downloadState.projectToOpen.downloadQueue[2].url:match(".*/(.-)$") or ""
        end
        table.remove(downloadState.projectToOpen.downloadQueue, 1)
        
        reaper.defer(downloads.processDownload)
    else
        if #downloadState.projectToOpen.extractQueue > 0 then
            reaper.defer(downloads.extractZipFiles)
        else
            local projectPath = downloadState.projectToOpen.tempDir .. "/project.rpp"
            
            -- Add to local projects
            local projects = require "projects"
            projects.addLocalProject(downloadState.projectToOpen.id, downloadState.projectName, projectPath)
            
            reaper.Main_openProject(projectPath)
            downloadState.isDownloading = false
            state.windowOpen = false
        end
    end
end

function downloads.openProject(projectId, projectUrl, staticFiles, projectName)
    if projectUrl and projectUrl ~= "" then
        state.activeScreen = "download_progress"
        downloads.startDownload(projectId, projectUrl, staticFiles, projectName or projectId)
        reaper.defer(downloads.processDownload)
    else
        reaper.ShowMessageBox("No project file available.", "Error", 0)
    end
end

return downloads