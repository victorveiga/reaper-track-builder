local auth = {}
local json = require "dkjson"
local r = reaper

-- Module state
local ctx
local state
local authState = {
    isAuthenticated = false,
    accessToken = "",
    email = "",
    verificationCode = "",
    isWaitingForCode = false,
    errorMessage = ""
}

-- API URLs
local baseUrl = "https://api.track-builder.com"
local loginUrl = baseUrl .. "/auth/login"
local verifyUrl = baseUrl .. "/auth/verify"

function auth.init(context, globalState)
    ctx = context
    state = globalState
end

function auth.isAuthenticated()
    return authState.isAuthenticated
end

function auth.getToken()
    return authState.accessToken
end

function auth.setToken(token)
    authState.accessToken = token
    authState.isAuthenticated = true
end

function auth.getState()
    return authState
end

function auth.saveToken(token)
    local configPath = reaper.GetResourcePath() .. "/Scripts/Track Builder Scripts/.auth"
    local file = io.open(configPath, "w")
    if file then
        file:write(token)
        file:close()
    end
end

function auth.loadToken()
    local configPath = reaper.GetResourcePath() .. "/Scripts/Track Builder Scripts/.auth"
    local file = io.open(configPath, "r")
    if file then
        local token = file:read("*a")
        file:close()
        return token
    end
    return nil
end

function auth.performLogout(showMessage)
    authState.isAuthenticated = false
    authState.accessToken = ""
    authState.email = ""
    authState.verificationCode = ""
    authState.isWaitingForCode = false
    authState.errorMessage = ""
    
    -- Reset data states
    state.songs = {}
    state.filteredSongs = {}
    state.projects = {}
    state.loadedSongs = false
    state.loadedProjects = false
    state.loadedLocalProjects = false
    
    -- Remove saved token
    local configPath = reaper.GetResourcePath() .. "/Scripts/Track Builder Scripts/.auth"
    os.remove(configPath)
    
    -- Show message if requested
    if showMessage then
        r.ShowMessageBox("Session expired. Please login again.", "Authentication Required", 0)
    end
    
    state.activeScreen = "login"
end

function auth.requestVerificationCode()
    local postData = string.format('{"email":"%s"}', authState.email)
    local tempFile = reaper.GetResourcePath() .. "/Temp/login_data.json"
    
    local file = io.open(tempFile, "w")
    file:write(postData)
    file:close()
    
    local command = string.format('curl -s -X POST -H "Content-Type: application/json" -d @"%s" %s', tempFile, loginUrl)
    local handle = io.popen(command)
    local response = handle:read("*a")
    handle:close()
    
    os.remove(tempFile)
    
    local data = json.decode(response)
    if data and data.success then
        authState.isWaitingForCode = true
        authState.errorMessage = ""
    else
        authState.errorMessage = data and data.message or "Failed to send verification code"
    end
end

function auth.verifyCode()
    local postData = string.format('{"email":"%s","code":"%s"}', authState.email, authState.verificationCode)
    local tempFile = reaper.GetResourcePath() .. "/Temp/verify_data.json"
    
    local file = io.open(tempFile, "w")
    file:write(postData)
    file:close()
    
    local command = string.format('curl -s -X POST -H "Content-Type: application/json" -d @"%s" %s', tempFile, verifyUrl)
    local handle = io.popen(command)
    local response = handle:read("*a")
    handle:close()
    
    os.remove(tempFile)
    
    local data = json.decode(response)
    if data and data.access_token then
        authState.accessToken = data.access_token
        authState.isAuthenticated = true
        authState.errorMessage = ""
        auth.saveToken(authState.accessToken)
        
        state.activeScreen = "menu"
        return true
    else
        authState.errorMessage = data and data.message or "Invalid verification code"
        return false
    end
end

function auth.setEmail(email)
    authState.email = email
end

function auth.setVerificationCode(code)
    authState.verificationCode = code
end

function auth.setErrorMessage(message)
    authState.errorMessage = message
end

function auth.setWaitingForCode(waiting)
    authState.isWaitingForCode = waiting
end

return auth