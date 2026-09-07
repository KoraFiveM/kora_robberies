local World = QbRobberies.world

CreateThread(function()
    local hydrated
    repeat
        hydrated = QB.callback.trigger('qbrobberies:server:hydrate')
        if not hydrated or not hydrated.ready then Wait(1500) end
    until hydrated and hydrated.ready
    World.apply(hydrated.robberies)
    QbRobberies.creator.setAdmin(hydrated.admin)
end)
