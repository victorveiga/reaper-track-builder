local uploads = {}
local r = reaper

-- Module dependencies
local ctx
local state
local auth
local api
local utils
local uploadState = {
    isUploading = false,
    currentProject = nil,
    progress = 0,
    message = "",
    errorMessage = ""
}

function uploads.init(context, globalState, authModule, apiModule, utilsModule)
    ctx = context
    state = globalState
    auth = authModule
    api = apiModule
    utils = utilsModule
end

function uploads.getState()
    return uploadState
end

function uploads.saveProjectToCloud(localProject)
    uploadState.isUploading = true
    uploadState.currentProject = localProject
    uploadState.progress = 0
    uploadState.message = "Reading RPP file..."
    uploadState.errorMessage = ""
    
    -- Read and encode RPP file
    local base64Content, readError = utils.readRppFileAsBase64(localProject.path)
    if not base64Content then
        uploadState.isUploading = false
        uploadState.errorMessage = "Error reading RPP file: " .. (readError or "Unknown error")
        return
    end
    
    uploadState.progress = 0.3
    uploadState.message = "Preparing upload data..."
    
    -- Get project songs from the cloud project if it exists
    local cloudProject = nil
    for _, project in ipairs(state.projects) do
        if project.id == localProject.id then
            cloudProject = project
            break
        end
    end
    
    -- Prepare the data for upload
    local uploadData = {
        id = localProject.id,
        name = localProject.name,
        songs = cloudProject and cloudProject.songs or {},
        rpp_file_base64 = base64Content
    }
    
    uploadState.progress = 0.5
    uploadState.message = "Uploading to cloud..."
    
    -- Make the PUT request
    local responseData = api.updateProject(uploadData)
    
    uploadState.progress = 0.8
    uploadState.message = "Processing response..."
    
    if responseData and responseData.message and responseData.message:match("successfully") then
        uploadState.progress = 1.0
        uploadState.message = "Upload completed successfully!"
        
        -- Update local project info if needed
        if responseData.rpp_file_url then
            -- Could store the cloud URL for reference
        end
        
        -- Auto-close upload dialog after success
        r.defer(function()
            uploadState.isUploading = false
            uploadState.currentProject = nil
            -- Reload projects to reflect changes
            state.loadedProjects = false
        end)
        
    else
        uploadState.isUploading = false
        uploadState.errorMessage = responseData and responseData.message or "Upload failed. Please try again."
    end
end

return uploads