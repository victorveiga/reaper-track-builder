local ui = {}
local r = reaper

-- Module dependencies
local ctx
local state
local auth
local api
local projects
local downloads
local uploads
local utils

-- ImGui Flags
local ImGui_WindowFlags_None = 0
local ImGui_ChildFlags_Border = 1
local ImGui_DragDropFlags_None = 0
local ImGui_ComboFlags_None = 0
local ImGui_SelectableFlags_None = 0

function ui.init(context, globalState, authModule, apiModule, projectsModule, downloadsModule, uploadsModule, utilsModule)
    ctx = context
    state = globalState
    auth = authModule
    api = apiModule
    projects = projectsModule
    downloads = downloadsModule
    uploads = uploadsModule
    utils = utilsModule
end

function ui.drawLoginScreen()
    local authState = auth.getState()
    
    r.ImGui_Text(ctx, 'Track Builder Login')
    r.ImGui_Separator(ctx)
    
    if authState.errorMessage ~= "" then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
        r.ImGui_Text(ctx, authState.errorMessage)
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_Separator(ctx)
    end
    
    if not authState.isWaitingForCode then
        r.ImGui_Text(ctx, "Enter your email to receive a verification code:")
        r.ImGui_Separator(ctx)
        
        r.ImGui_SetNextItemWidth(ctx, 300)
        local changed, newEmail = r.ImGui_InputText(ctx, "Email", authState.email)
        if changed then
            auth.setEmail(newEmail)
        end
        
        r.ImGui_Separator(ctx)
        
        if r.ImGui_Button(ctx, 'Send Verification Code') then
            if authState.email ~= "" then
                auth.requestVerificationCode()
            else
                auth.setErrorMessage("Please enter an email address")
            end
        end
    else
        r.ImGui_Text(ctx, string.format("Verification code sent to: %s", authState.email))
        r.ImGui_Separator(ctx)
        
        r.ImGui_Text(ctx, "Enter the verification code:")
        r.ImGui_SetNextItemWidth(ctx, 200)
        local changed, newCode = r.ImGui_InputText(ctx, "Code", authState.verificationCode)
        if changed then
            auth.setVerificationCode(newCode)
        end
        
        r.ImGui_Separator(ctx)
        
        if r.ImGui_Button(ctx, 'Verify Code') then
            if authState.verificationCode ~= "" then
                if auth.verifyCode() then
                    -- Reload data after successful login
                    state.loadedSongs = false
                    state.loadedProjects = false
                    state.loadedLocalProjects = false
                    
                    state.songs = api.getSongs() or {}
                    state.filteredSongs = state.songs
                    state.loadedSongs = true
                    
                    state.projects = api.getProjects() or {}
                    state.loadedProjects = true
                    
                    projects.loadLocalProjects()
                    state.loadedLocalProjects = true
                end
            else
                auth.setErrorMessage("Please enter the verification code")
            end
        end
        
        r.ImGui_SameLine(ctx)
        
        if r.ImGui_Button(ctx, 'Back') then
            auth.setWaitingForCode(false)
            auth.setVerificationCode("")
            auth.setErrorMessage("")
        end
    end
end

function ui.drawUploadProgressScreen()
    local uploadState = uploads.getState()
    
    r.ImGui_Text(ctx, 'Uploading Project to Cloud')
    r.ImGui_Separator(ctx)
    
    if uploadState.currentProject then
        r.ImGui_Text(ctx, "Project: " .. uploadState.currentProject.name)
        r.ImGui_Separator(ctx)
    end
    
    r.ImGui_ProgressBar(ctx, uploadState.progress, -1, 0, string.format("%.0f%%", uploadState.progress * 100))
    r.ImGui_Text(ctx, uploadState.message)
    
    if uploadState.errorMessage ~= "" then
        r.ImGui_Separator(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
        r.ImGui_Text(ctx, "Error: " .. uploadState.errorMessage)
        r.ImGui_PopStyleColor(ctx)
    end
    
    r.ImGui_Separator(ctx)
    
    if not uploadState.isUploading or uploadState.errorMessage ~= "" then
        if r.ImGui_Button(ctx, 'Close') then
            uploadState.isUploading = false
            uploadState.currentProject = nil
            uploadState.errorMessage = ""
            state.activeScreen = "menu"
        end
    end
end

function ui.drawSelectionScreen()
    r.ImGui_Text(ctx, 'Select Songs')
    r.ImGui_Separator(ctx)

    local changed
    changed, state.searchQuery = r.ImGui_InputText(ctx, "Search", state.searchQuery, 256)
    if changed then
        state.filteredSongs = utils.filterSongs(state.songs, state.searchQuery)
    end

    r.ImGui_Separator(ctx)

    local startIdx = ((state.currentPage - 1) * state.songsPerPage) + 1
    local endIdx = math.min(startIdx + state.songsPerPage - 1, #state.filteredSongs)

    if r.ImGui_BeginChild(ctx, 'SongList', 0, 280, ImGui_ChildFlags_Border) then
        for i = startIdx, endIdx do
            local song = state.filteredSongs[i]
            if song then
                local isSelected = state.selectedSongs[song.id] or false
                local displayName = string.format("%s (%s)", song.title, song.artist or "Unknown")
                local changed, checked = r.ImGui_Checkbox(ctx, displayName, isSelected)
                if changed then
                    state.selectedSongs[song.id] = checked
                end
            end
        end
        r.ImGui_EndChild(ctx)
    end

    r.ImGui_Separator(ctx)

    local totalPages = math.ceil(#state.filteredSongs / state.songsPerPage)
    r.ImGui_Text(ctx, string.format("Page %d of %d", state.currentPage, totalPages))    

    if state.currentPage > 1 then
        if r.ImGui_Button(ctx, 'Previous') then
            state.currentPage = state.currentPage - 1
        end
        r.ImGui_SameLine(ctx)
    end

    if state.currentPage < totalPages then
        if r.ImGui_Button(ctx, 'Next') then
            state.currentPage = state.currentPage + 1
        end
        r.ImGui_SameLine(ctx)
    end

    if r.ImGui_Button(ctx, 'Confirm Selection') then
        state.orderedSongs = {}
        for songId, selected in pairs(state.selectedSongs) do
            if selected then
                for _, song in ipairs(state.songs) do
                    if song.id == songId then
                        table.insert(state.orderedSongs, song)
                        break
                    end
                end
            end
        end
        state.activeScreen = "create_projects"
    end

    if r.ImGui_Button(ctx, 'Back') then
        state.activeScreen = "menu"
    end
end

function ui.drawProjectScreen()
    if #state.orderedSongs > 0 and not next(state.songKeys) then
        utils.initializeSongKeys(state.orderedSongs, state.songKeys)
    end

    if state.needsReorder then
        if utils.reorderSongs(state.orderedSongs, state.moveFrom, state.moveTo) then
            state.moveFrom = -1
            state.moveTo = -1
            state.needsReorder = false
        end
    end

    r.ImGui_Text(ctx, 'Create New Project')
    r.ImGui_Separator(ctx)
    
    local changed
    changed, state.projectName = r.ImGui_InputText(ctx, "Project Name", state.projectName, 256)
    changed, state.eventDate = r.ImGui_InputText(ctx, "Event Date", state.eventDate, 256)
    
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, 'Arrange Songs and Select Keys')
    
    local comboWidth = 80
    
    if r.ImGui_BeginChild(ctx, 'OrderedSongs', 0, 200, ImGui_ChildFlags_Border) then
        for i, song in ipairs(state.orderedSongs) do
            r.ImGui_PushID(ctx, i)
            
            r.ImGui_BeginGroup(ctx)
            
            local selectableWidth = 280
            local isSelected = false
            local displayText = string.format("%d. %s (%s)", i, song.title, song.artist or "Unknown")
            if r.ImGui_Selectable(ctx, displayText, isSelected, 0, selectableWidth, 20) then
                isSelected = true
            end
            
            if r.ImGui_BeginDragDropSource(ctx, ImGui_DragDropFlags_None) then
                state.moveFrom = i
                r.ImGui_SetDragDropPayload(ctx, 'SONG_REORDER', tostring(i))
                r.ImGui_Text(ctx, "Moving: " .. song.title)
                r.ImGui_EndDragDropSource(ctx)
            end
            
            if r.ImGui_BeginDragDropTarget(ctx) then
                local payload = r.ImGui_AcceptDragDropPayload(ctx, 'SONG_REORDER')
                if payload then
                    state.moveTo = i
                    state.needsReorder = true
                end
                r.ImGui_EndDragDropTarget(ctx)
            end
            
            r.ImGui_SameLine(ctx, 300)
            
            local currentKey = state.songKeys[song.id] or song.key or "C"
            local currentKeyIndex = utils.findKeyIndex(currentKey, state.keys)
            
            r.ImGui_SetNextItemWidth(ctx, comboWidth)
            local changed, newIndex = r.ImGui_Combo(ctx, "##key" .. i, currentKeyIndex, table.concat(state.keys, "\0") .. "\0")
            if changed then
                state.songKeys[song.id] = state.keys[newIndex + 1]
            end
            
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, string.format("(Original: %s)", song.key or "?"))
            
            r.ImGui_EndGroup(ctx)
            r.ImGui_PopID(ctx)
            
            if i < #state.orderedSongs then
                r.ImGui_Separator(ctx)
            end
        end
        r.ImGui_EndChild(ctx)
    end
    
    r.ImGui_Separator(ctx)

    if r.ImGui_Button(ctx, 'Create Project') then
        projects.createProject()
    end
    
    r.ImGui_SameLine(ctx)
    
    if r.ImGui_Button(ctx, 'Back') then
        state.activeScreen = "songs"
    end
end

function ui.drawProjectsList()
    r.ImGui_Text(ctx, 'Your Projects')
    
    r.ImGui_Separator(ctx)
    
    local startIdx = ((state.currentProjectPage - 1) * state.projectsPerPage) + 1
    local endIdx = math.min(startIdx + state.projectsPerPage - 1, #state.projects)
    
    if r.ImGui_BeginChild(ctx, 'ProjectList', 0, 280, ImGui_ChildFlags_Border) then
        for i = startIdx, endIdx do
            local project = state.projects[i]
            if project then
                r.ImGui_Text(ctx, "Project: " .. project.name)
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Open##" .. project.id) then
                    downloads.openProject(project.id, project.zip_file, project.static_files, project.name)
                end
            end
        end
        r.ImGui_EndChild(ctx)
    end
    
    r.ImGui_Separator(ctx)
    
    -- Pagination controls for projects
    local totalProjectPages = math.ceil(#state.projects / state.projectsPerPage)
    r.ImGui_Text(ctx, string.format("Page %d of %d", state.currentProjectPage, totalProjectPages))
    
    if state.currentProjectPage > 1 then
        if r.ImGui_Button(ctx, 'Previous##Projects') then
            state.currentProjectPage = state.currentProjectPage - 1
        end
        r.ImGui_SameLine(ctx)
    end
    
    if state.currentProjectPage < totalProjectPages then
        if r.ImGui_Button(ctx, 'Next##Projects') then
            state.currentProjectPage = state.currentProjectPage + 1
        end
        r.ImGui_SameLine(ctx)
    end
    
    if r.ImGui_Button(ctx, 'Back') then
        state.activeScreen = "menu"
    end
end

function ui.drawMenu()
    r.ImGui_Text(ctx, 'Main Menu')
    r.ImGui_Separator(ctx)
    
    -- Local projects section
    r.ImGui_Text(ctx, 'Local Projects')
    r.ImGui_Separator(ctx)
    
    if r.ImGui_BeginChild(ctx, 'LocalProjectsList', 0, 200, ImGui_ChildFlags_Border) then
        if #state.localProjects == 0 then
            r.ImGui_Text(ctx, 'No local projects found')
        else
            for _, project in ipairs(state.localProjects) do
                r.ImGui_BeginGroup(ctx)
                r.ImGui_Text(ctx, string.format("Project: %s", project.name))
                if project.downloadedAt then
                    r.ImGui_Text(ctx, string.format("Downloaded: %s", project.downloadedAt))
                end
                
                r.ImGui_SameLine(ctx, 280)
                
                if r.ImGui_Button(ctx, 'Open##local' .. project.id) then
                    projects.openLocalProject(project.path)
                end
                
                r.ImGui_SameLine(ctx)
                
                if r.ImGui_Button(ctx, 'Save to Cloud##local' .. project.id) then
                    state.activeScreen = "upload_progress"
                    uploads.saveProjectToCloud(project)
                end
                
                r.ImGui_SameLine(ctx)
                
                if r.ImGui_Button(ctx, 'Delete##local' .. project.id) then
                    local result = r.ShowMessageBox(
                        string.format("Are you sure you want to delete the project '%s'?\n\nThis will permanently remove the project files from your computer.", 
                        project.name),
                        "Confirm Delete",
                        4  -- MB_YESNO
                    )
                    if result == 6 then  -- IDYES
                        if projects.deleteLocalProject(project.id) then
                            r.ShowMessageBox("Project deleted successfully.", "Success", 0)
                        else
                            r.ShowMessageBox("Failed to delete project.", "Error", 0)
                        end
                    end
                end
                
                r.ImGui_EndGroup(ctx)
                r.ImGui_Separator(ctx)
            end
        end
        r.ImGui_EndChild(ctx)
    end
    
    r.ImGui_Separator(ctx)
    
    -- Menu options
    if r.ImGui_Button(ctx, 'Create New Project') then
        state.activeScreen = "songs"
    end
    
    if r.ImGui_Button(ctx, 'List Projects from Cloud') then
        state.activeScreen = "projects"
    end
    
    if r.ImGui_Button(ctx, 'Logout') then
        auth.performLogout(false)
    end
    
    if r.ImGui_Button(ctx, 'Exit') then
        state.windowOpen = false
    end
end

function ui.drawDownloadProgressScreen()
    local downloadState = downloads.getState()
    
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
        state.activeScreen = "projects"
    end
end

function ui.draw()
    r.ImGui_SetNextWindowSize(ctx, 700, 600, r.ImGui_Cond_FirstUseEver())
    
    local visible, open = r.ImGui_Begin(ctx, 'Track Builder', true, ImGui_WindowFlags_None)
    state.windowOpen = open
    
    if visible then
        if state.activeScreen == "login" then
            ui.drawLoginScreen()
        elseif state.activeScreen == "menu" then
            ui.drawMenu()
        elseif state.activeScreen == "songs" then
            ui.drawSelectionScreen()
        elseif state.activeScreen == "projects" then
            ui.drawProjectsList()
        elseif state.activeScreen == "create_projects" then
            ui.drawProjectScreen()
        elseif state.activeScreen == "download_progress" then
            ui.drawDownloadProgressScreen()
        elseif state.activeScreen == "upload_progress" then
            ui.drawUploadProgressScreen()
        end
        r.ImGui_End(ctx)
    end
end

return ui