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
    local fezzedTechItems = assets.json("/fezzedtech-items.json")
    for _, item in pairs(fezzedTechItems) do
        table.insert(sipCustomItems, item)
    end
    assets.erase("/sipCustomItems.json")
    assets.add("/sipCustomItems.json", sipCustomItems)
end
::skipSip::