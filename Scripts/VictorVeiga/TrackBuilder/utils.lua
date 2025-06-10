local utils = {}
local r = reaper

-- Base64 encoding function
function utils.encodeBase64(data)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local result = {}
    
    for i = 1, #data, 3 do
        local a, b, c = string.byte(data, i), string.byte(data, i+1), string.byte(data, i+2)
        local bitmap = a * 0x10000 + (b or 0) * 0x100 + (c or 0)
        
        result[#result+1] = b64chars:sub(((bitmap >> 18) & 63) + 1, ((bitmap >> 18) & 63) + 1)
        result[#result+1] = b64chars:sub(((bitmap >> 12) & 63) + 1, ((bitmap >> 12) & 63) + 1)
        result[#result+1] = b and b64chars:sub(((bitmap >> 6) & 63) + 1, ((bitmap >> 6) & 63) + 1) or '='
        result[#result+1] = c and b64chars:sub((bitmap & 63) + 1, (bitmap & 63) + 1) or '='
    end
    
    return table.concat(result)
end

-- Function to read RPP file and encode to base64
function utils.readRppFileAsBase64(filePath)
    local file = io.open(filePath, "rb")
    if not file then
        return nil, "Could not open file: " .. filePath
    end
    
    local content = file:read("*a")
    file:close()
    
    if not content or content == "" then
        return nil, "File is empty or could not be read"
    end
    
    local base64Content = utils.encodeBase64(content)
    return base64Content, nil
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

function utils.fileExists(path)
    return reaper.file_exists(path)
end

function utils.getOS()
    return reaper.GetOS()
end

function utils.findKeyIndex(key, keys)
    for i, k in ipairs(keys) do
        if k == key then
            return i - 1
        end
    end
    return 0
end

function utils.filterSongs(songs, searchQuery)
    local filteredSongs = {}
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
    return filteredSongs
end

function utils.reorderSongs(orderedSongs, moveFrom, moveTo)
    if moveFrom > 0 and moveTo > 0 and moveFrom ~= moveTo then
        local temp = table.remove(orderedSongs, moveFrom)
        table.insert(orderedSongs, moveTo, temp)
        return true
    end
    return false
end

function utils.initializeSongKeys(orderedSongs, songKeys)
    for _, song in ipairs(orderedSongs) do
        if not songKeys[song.id] then
            songKeys[song.id] = song.key or "C"
        end
    end
end

return utils