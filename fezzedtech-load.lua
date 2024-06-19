-- FezzedTech loading script --

-- No logged errors on xSB-2.
if xsb and assets.exists then 
    if not assets.exists("/sipCustomItems.json") then
        goto skipSip
    end
end

-- Will log an error on OpenStarbound. Annoying.
local sipFound, sipCustomItems = pcall(assets.json, "/sipCustomItems.json")
if sipFound then
    if xsb and assets.exists then
        if assets.exists("/xSIP.lua") then
            local xSipVersion = (function()
                for _, path in ipairs(assets.loadedSources()) do
                    local metadata = assets.sourceMetadata(path)
                    if metadata and metadata.name == "xSIP" then
                        return metadata.version or "[unknown version]"
                    end
                end
                return "[unknown version]"
            end) ()
            sb.logInfo("[FezzedTech] Detected xSB-2 v%s and xSIP %s; adding FezzedTech items...", xsb.version(), xSipVersion)
        else
            goto skipSip
        end
    else
        if pcall(assets.bytes, "/xSIP.lua") then
            local detectedEngineMod = xsb and ("xSB-2 v" .. xsb.version()) or "OpenStarbound (or fork)"
            sb.logInfo("[FezzedTech] Detected %s and xSIP; adding FezzedTech items...", detectedEngineMod)
        else
            goto skipSip
        end
    end

    local function getPath(itemName)
        local sipItems = assets.json("/sipItemDump.json")
        for _, item in pairs(sipItems) do
            if item.name == itemName then
                return item.path, item.fileName
            end
        end
        return "/", "fezzedtech-items.json"
    end

    local fezzedTechItems = assets.json("/fezzedtech-items.json")
    for _, item in pairs(fezzedTechItems) do
        local parameters = item.parameters or jobject{}
        local path, fileName = getPath(item.name)
        table.insert(sipCustomItems, {
            path = path,
            fileName = fileName,
            name = item.name,
            parameters = parameters,
            rarity = "legendary",
            directives = parameters.directives,
            shortdescription = parameters.shortdescription or (item.name .. "^orange;<custom>^reset;"),
            icon = type(parameters.inventoryIcon) == "string" and parameters.inventoryIcon or "/assetmissing.png",
            race = "generic",
            category = parameters.category or "tool",
        })
    end
    assets.erase("/sipCustomItems.json")
    assets.add("/sipCustomItems.json", sipCustomItems)
end
::skipSip::
