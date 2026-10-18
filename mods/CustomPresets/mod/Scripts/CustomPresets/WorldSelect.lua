local M = {}
local layouts = {}
local hooked = false
local function valid(widget) return widget and widget:IsValid() end

function M.installHooks()
    if hooked then return end
    local class='/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSelect.WBP_Title_WorldSelect_C'
    local path=class..':Update Local World List Content'
    if not valid(StaticFindObject(path)) then return end
    RegisterHook(path,function()
        -- Hide the old footer before native rebuilding inserts its replacement.
        for _, entry in pairs(layouts) do
            if valid(entry.Button) then entry.Button:SetVisibility(1) end
        end
    end,function()
        M.update()
        for _, entry in pairs(layouts) do
            if valid(entry.Button) then entry.Button:SetVisibility(0) end
        end
    end)
    hooked=true
end

function M.start()
    -- Register before the first world-selection screen can build its list.
    pcall(LoadAsset,'/Game/Pal/Blueprint/UI/UserInterface/Title/WBP_Title_WorldSelect.WBP_Title_WorldSelect_C')
    M.installHooks()
    local queued=false
    LoopAsync(100,function()
        if queued then return end
        queued=true
        ExecuteInGameThread(function()
            local ok,err=pcall(M.update)
            queued=false
            if not ok then print('[CustomPresets] '..tostring(err)..'\n') end
        end)
    end)
end

function M.update()
    local scrollClass=StaticFindObject('/Script/UMG.ScrollBox')
    local canvasClass=StaticFindObject('/Script/UMG.CanvasPanel')
    for key, entry in pairs(layouts) do
        if not valid(entry.Scroll) then layouts[key]=nil end
    end
    for _, button in ipairs(FindAllOf('WBP_Title_WorldSelect_CreateWorld_ListContent_C') or {}) do
        if valid(button) then
            local scroll=button:GetParent()
            if valid(scroll) and scroll:IsA(scrollClass) then
                local canvas=scroll:GetParent()
                if valid(canvas) and canvas:IsA(canvasClass) then
                    local key=scroll:GetFullName()
                    local entry=layouts[key]
                    -- Measure against the full original viewport after a native
                    -- rebuild, not the reduced viewport used by the fixed footer.
                    if entry then scroll.Slot:SetOffsets(entry.Offsets) end
                    scroll:ForceLayoutPrepass()
                    local fraction=scroll:GetViewFraction()
                    local distance=scroll:GetScrollOffsetOfEnd()
                    local overflowing=(fraction>0 and fraction<0.999) or distance>1
                    if not overflowing then
                        if entry and valid(entry.Button) and entry.Button~=button then entry.Button:RemoveFromParent() end
                        layouts[key]=nil
                        button:SetVisibility(0)
                    else
                        if not entry then
                            local slot=scroll.Slot
                            local offsets=slot:GetOffsets()
                            local anchors=slot:GetAnchors()
                            -- Reserve a fixed footer within the original list bounds.
                            entry={Scroll=scroll,Anchors=anchors,
                                Offsets={Left=offsets.Left,Top=offsets.Top,Right=offsets.Right,Bottom=offsets.Bottom}}
                            layouts[key]=entry
                        end
                        local offsets=entry.Offsets
                        scroll.Slot:SetOffsets({Left=offsets.Left,Top=offsets.Top,Right=offsets.Right,Bottom=offsets.Bottom+72})
                        -- List refreshes can create another native button. Keep its
                        -- original delegates while replacing the previous fixed footer.
                        if valid(entry.Button) and entry.Button~=button then entry.Button:RemoveFromParent() end
                        button:RemoveFromParent()
                        local slot=canvas:AddChildToCanvas(button)
                        slot:SetAnchors({Minimum={X=entry.Anchors.Minimum.X,Y=1},Maximum={X=entry.Anchors.Maximum.X,Y=1}})
                        slot:SetAlignment({X=0,Y=1})
                        slot:SetOffsets({Left=offsets.Left,Top=-offsets.Bottom,Right=offsets.Right,Bottom=64})
                        slot:SetAutoSize(false)
                        slot:SetZOrder(2)
                        entry.Button=button
                        button:SetVisibility(0)
                    end
                end
            end
        end
    end
end
return M
