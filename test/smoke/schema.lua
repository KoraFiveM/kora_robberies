local H = dofile('test/harness.lua')

Config = { Robberies = { defaultCooldown = 1800, defaultMinPolice = 0, maxSteps = 20, maxProps = 30 } }
QbRobberies = {}
dofile('shared/schema.lua')
local S = QbRobberies.schema

local definition, err = S.normalise({
    id = 'Pacific Standard!', label = 'Pacific Standard', start = { x = 1, y = 2, z = 3 },
    steps = { { kind = 'hack', label = 'Hack terminal', coords = { x = 2, y = 3, z = 4 }, rewards = {
        { kind = 'money', name = 'cash', min = 100, max = 300, chance = 50 },
    }, unlockDoors = { 'pacific-vault' } } },
    props = { { model = 'prop_ld_int_safe_01', coords = { x = 2, y = 3, z = 4, w = 90 } } },
})
H.ok(definition, err)
H.equal(definition.id, 'pacific_standard', 'ids are normalized')
H.equal(definition.steps[1].game.type, 'hacking', 'hack defaults to a proof-backed game')
H.equal(definition.steps[1].game.opts.solutionsize, 5, 'challenge options are normalized and persisted')
H.equal(definition.props[1].coords.w, 90, 'prop heading survives normalization')

local bad, badErr = S.normalise({ id = 'bad', label = 'Bad', start = { x = 1, y = 2, z = 3 }, steps = { { kind = 'x', label = 'no', coords = { x = 1, y = 1, z = 1 } } } })
H.rejects(bad, badErr, 'unknown step kinds are rejected')

local reward, rewardErr = S.normaliseReward({ kind = 'money', name = 'crypto', min = 1, max = 1, chance = 100 })
H.rejects(reward, rewardErr, 'only supported money accounts are accepted')
H.finish('schema')
