-- FezzedTech loading script --

if xsb then
    sb.logInfo("[FezzedTech] Detected xSB-2 v" .. xsb.version() .. ".")
else
    sb.logInfo("[FezzedTech] Detected OpenStarbound or similar.")
end

local sipFound, sipCustomItems = pcall(assets.json, "/sipCustomItems.json")
if sipFound then
    if pcall(assets.bytes, "/xSIP.lua") then
        sb.logInfo("[FezzedTech] Detected xSIP; adding FezzedTech items...")
    else
        goto skipSip
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
