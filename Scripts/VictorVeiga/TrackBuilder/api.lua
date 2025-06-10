local api = {}
local json = require "dkjson"
local r = reaper

-- Module dependencies
local auth

-- API URLs
local baseUrl = "https://api.track-builder.com"
local songsUrl = baseUrl .. "/songs"
local projectsUrl = baseUrl .. "/projects?user_id=4aaca8b3-a6b7-4100-9080-5b761948682c"
local projectCreateUrl = baseUrl .. "/projects"

function api.init(authModule)
    auth = authModule
end

function api.isAuthenticationError(response)
    if not response or response == "" then
        return false
    end
    
    local data = json.decode(response)
    if data then
        -- Check for 403 Forbidden or Unauthorized errors
        if (data.error and (data.error:match("Unauthorized") or data.error:match("Forbidden"))) or
           (data.status and (data.status == 403 or data.status == 401)) or
           (data.message and (data.message:match("Unauthorized") or data.message:match("Forbidden"))) then
            return true
        end
    end
    
    return false
end

function api.makeAuthenticatedRequest(url, method, data)
    local headers = string.format('-H "Authorization: Bearer %s" -H "Content-Type: application/json"', auth.getToken())
    local command
    
    if method == "GET" then
        command = string.format('curl -s %s "%s"', headers, url)
    elseif method == "POST" and data then
        local tempFile = reaper.GetResourcePath() .. "/Temp/request_data.json"
        local file = io.open(tempFile, "w")
        file:write(data)
        file:close()
        command = string.format('curl -s -X POST %s -d @"%s" "%s"', headers, tempFile, url)
    elseif method == "PUT" and data then
        local tempFile = reaper.GetResourcePath() .. "/Temp/request_data.json"
        local file = io.open(tempFile, "w")
        file:write(data)
        file:close()
        command = string.format('curl -s -X PUT %s -d @"%s" "%s"', headers, tempFile, url)
    else
        command = string.format('curl -s -X %s %s "%s"', method, headers, url)
    end
    
    local handle = io.popen(command)
    local response = handle:read("*a")
    handle:close()
    
    if (method == "POST" or method == "PUT") and data then
        os.remove(reaper.GetResourcePath() .. "/Temp/request_data.json")
    end
    
    return response
end

function api.getSongs()
    local response = api.makeAuthenticatedRequest(songsUrl, "GET")
    
    if response == "" then
        r.ShowMessageBox("Could not connect to the API. Check your connection.", "Error", 0)
        return nil
    end
    
    -- Check for authentication errors
    if api.isAuthenticationError(response) then
        r.defer(function() auth.performLogout(true) end)
        return nil
    end
    
    local data, _, err = json.decode(response)
    if err then
        r.ShowMessageBox("Error loading songs: " .. err, "Error", 0)
        return nil
    end
    
    return data.items
end

function api.getProjects()
    local response = api.makeAuthenticatedRequest(projectsUrl, "GET")
    
    if response == "" then
        r.ShowMessageBox("Could not connect to the API. Check your connection.", "Error", 0)
        return nil
    end
    
    -- Check for authentication errors
    if api.isAuthenticationError(response) then
        r.defer(function() auth.performLogout(true) end)
        return nil
    end
    
    local data, _, err = json.decode(response)
    if err then
        r.ShowMessageBox("Error loading projects: " .. err, "Error", 0)
        return nil
    end
    
    return data.items
end

function api.createProject(projectData)
    local jsonData = json.encode(projectData)
    local response = api.makeAuthenticatedRequest(projectCreateUrl, "POST", jsonData)
    
    -- Check for authentication errors
    if api.isAuthenticationError(response) then
        r.defer(function() auth.performLogout(true) end)
        return nil
    end
    
    return json.decode(response)
end

function api.updateProject(projectData)
    local jsonData = json.encode(projectData)
    local response = api.makeAuthenticatedRequest(projectCreateUrl, "PUT", jsonData)
    
    -- Check for authentication errors
    if api.isAuthenticationError(response) then
        r.defer(function() auth.performLogout(true) end)
        return nil
    end
    
    return json.decode(response)
end

return api