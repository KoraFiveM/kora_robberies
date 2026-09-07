local H = { passed = 0 }

function H.ok(value, message)
    if not value then error(message or 'expected truthy value', 2) end
    H.passed = H.passed + 1
end

function H.equal(actual, expected, message)
    if actual ~= expected then error(('%s: expected %s, got %s'):format(message or 'values differ', tostring(expected), tostring(actual)), 2) end
    H.passed = H.passed + 1
end

function H.rejects(value, err, message)
    H.ok(not value and type(err) == 'string' and err ~= '', message or 'expected rejection')
end

function H.finish(name)
    print(('%s: %d passed'):format(name, H.passed))
end

return H
