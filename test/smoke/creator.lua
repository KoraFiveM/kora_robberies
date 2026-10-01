-- Run from qbrobberies: lua test/smoke/creator.lua [creator-source]
local H = dofile('test/harness.lua')
local response, app, opens, zones, placements = nil, nil, 0, 0, 0
local mutations, hashes, notices, dialogs = {}, {}, {}, {}
local captured = { type = 'sphere', opts = { coords = { x = 11, y = 22, z = 33 }, radius = 1.5 } }
local placed = { coords = { x = 44, y = 55, z = 66 }, heading = 90 }
QB = {
    notify = { send = function(payload) notices[#notices + 1] = payload end },
    zones = { startCreator = function(kind) H.equal(kind, 'sphere', 'steps retain sphere placement'); zones = zones + 1; return captured end },
    placement = { start = function(model) placements = placements + 1; H.equal(model, 'prop_ld_int_safe_01', 'selected model reaches placement'); return placed end },
    nui = {
        openInputDialog = function(fields, title, description)
            dialogs[#dialogs + 1] = { fields = fields, title = title, description = description }
            return response
        end,
        registerApp = function(definition) app = definition end,
        openApp = function(id, opts)
            H.equal(id, 'qbrobberies:creator', 'existing app id retained')
            H.equal(opts.viewId, 'robbery:test', 'creator returns to selected robbery')
            opens = opens + 1
        end,
    },
}
CreateThread = function(fn) fn() end
RegisterCommand = function() end
joaat = function(model) hashes[#hashes + 1] = model; return model end
IsModelValid = function() return true end -- Native validity is outside this response-contract check.
Config, QbRobberies = {}, {}
dofile('config.lua')
dofile('shared/schema.lua')
local definition = assert(QbRobberies.schema.normalise({ id = 'test', label = 'Test robbery', start = { x = 0, y = 0, z = 0 }, steps = {}, props = {} }))
QB.callback = { trigger = function(name, id, payload)
    if name == 'qbrobberies:server:hydrate' then return { admin = true, robberies = { definition } } end
    mutations[#mutations + 1] = { name = name, id = id, payload = payload }
    return definition
end }
dofile(arg[1] or 'client/creator.lua')
local Creator = QbRobberies.creator
Creator.setAdmin(true)
Creator.open('test')
local function action(id, result)
    response = result
    local before = opens
    H.equal(app.onAction(id, { viewId = 'robbery:test' }), nil, 'existing asynchronous action return retained')
    H.equal(opens, before + 1, 'flow reopens creator once')
end

action('creator:add-step-flow', { values = { kind = 'drill', label = 'Force the vault', duration = 12345, radius = 2.5, gameType = 'hacking', difficulty = 'hard' } })
local step = mutations[1]
H.equal(step.name, 'qbrobberies:server:addStep', 'existing step callback retained')
H.equal(step.id, 'test', 'step robbery id retained')
H.equal(step.payload.kind, 'drill', 'selected step kind survives response envelope')
H.equal(step.payload.label, 'Force the vault', 'selected prompt survives response envelope')
H.equal(step.payload.duration, 12345, 'selected duration survives response envelope')
H.equal(step.payload.radius, 2.5, 'selected radius survives response envelope')
H.equal(step.payload.coords.x, 11, 'world-captured coordinates retained')
H.equal(step.payload.game.type, 'hacking', 'selected challenge survives response envelope')
H.equal(step.payload.game.opts.solutionsize, 7, 'selected hard challenge preset retained')
H.equal(step.payload.game.opts.timeout, 20, 'selected hard challenge timeout retained')
H.equal(dialogs[1].fields[1].id, 'kind', 'existing step fields retained')
H.equal(dialogs[1].title, 'New robbery step', 'existing step dialog title retained')
H.equal(notices[1].type, 'success', 'successful step notification retained')

action('creator:add-prop-flow', { values = { model = 'prop_ld_int_safe_01' } })
local prop = mutations[2]
H.equal(prop.name, 'qbrobberies:server:addProp', 'existing prop callback retained')
H.equal(prop.id, 'test', 'prop robbery id retained')
H.equal(hashes[1], 'prop_ld_int_safe_01', 'selected model reaches native hash boundary')
H.equal(prop.payload.model, 'prop_ld_int_safe_01', 'selected model reaches server payload')
H.equal(prop.payload.coords.x, 44, 'placement coordinates retained')
H.equal(prop.payload.coords.w, 90, 'placement heading retained')
H.equal(dialogs[2].fields[1].id, 'model', 'existing prop field retained')
H.equal(dialogs[2].title, 'Place a local robbery prop', 'existing prop dialog title retained')
H.equal(notices[2].type, 'success', 'successful prop notification retained')

for _, id in ipairs({ 'creator:add-step-flow', 'creator:add-prop-flow' }) do
    for _, result in ipairs({ { cancelled = true }, false }) do
        action(id, result)
        H.equal(zones, 1, 'cancelled/failed dialog starts no new zone')
        H.equal(placements, 1, 'cancelled/failed dialog starts no new placement')
        H.equal(#hashes, 1, 'cancelled/failed dialog does not hash a missing model')
        H.equal(#mutations, 2, 'cancelled/failed dialog sends no mutation')
    end
    action(id, nil)
    H.equal(zones, 1, 'nil dialog starts no new zone')
    H.equal(placements, 1, 'nil dialog starts no new placement')
    H.equal(#mutations, 2, 'nil dialog sends no mutation')
end
H.finish('creator')
