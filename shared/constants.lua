Limits = {
    lists = 100,        -- item lists
    listItems = 30,     -- different items in one list
    itemAmount = 1000,  -- amount of one item
    props = 100,        -- props in one shell setup
    searchResults = 24, -- results shown when adding items
}

-- Controls a progress bar can block while a prop is searched.
ProgressDisableOptions = {
    { value = 'move', label = 'Movement' },
    { value = 'combat', label = 'Combat' },
    { value = 'car', label = 'Vehicle (car)' },
    { value = 'vehicle', label = 'Vehicle (vehicle)' },
}

-- What a newly placed prop searches with. Every prop can change its own (time, animation, disabled controls);
-- the config's defaults are only the starting values.
do
    local defaults = Config.Robberies.House.defaults
    local anim = defaults.searchAnim or {}
    DefaultSearch = {
        time = defaults.searchTime or 5000,
        progressLabel = defaults.searchLabel or 'Searching...',
        anim = { dict = anim.dict or 'mp_arresting', clip = anim.clip or 'a_uncuff', flag = anim.flag or anim.flags or 49 },
        disable = defaults.searchDisable or { vehicle = true, move = true, combat = true },
    }
end
