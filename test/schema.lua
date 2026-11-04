-- Run from the resource directory: lua test/schema.lua
Kora = { sql = { NULL = '\0qbsql:null\0' } }
dofile('server/schema.lua')

local expected = { kora_robberies_houses = 108, kora_robberies_lists = 11, kora_robberies_shells = 6, kora_robberies_stores = 19 }
assert(#QBRobberiesSchema == 4, 'four tables declared')
for _, spec in ipairs(QBRobberiesSchema) do
    assert(expected[spec.name], spec.name .. ' is expected')
    assert(spec.primary[1] == 'id', spec.name .. ' keeps id as the primary key, so INSERT IGNORE matches the old INSERT')
    assert(#spec.seed.rows == expected[spec.name], spec.name .. ' keeps every bundled row')
    for _, row in ipairs(spec.seed.rows) do assert(type(row.id) == 'string' and row.data:sub(1, 1) == '{') end
    expected[spec.name] = nil
end
assert(next(expected) == nil, 'every table is declared')

local manifest = assert(io.open('fxmanifest.lua')):read('a')
assert(manifest:find("'server/schema.lua'", 1, true) and not manifest:find('.sql\'', 1, true), 'manifest loads the schema, not a sql file')
print('qbrobberies: schema declares its tables and seed rows')
