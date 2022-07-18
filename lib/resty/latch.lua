local _VERSION = "0.1.0"
local sleep = ngx.sleep
local min = math.min
local max = math.max

---@class resty.latch
_M = {}

---@class resty.latch.opts
---@field exptime number?
---@field timeout number?
---@field step number?
---@field ratio number?
---@field max_step number?

---comment create a new instance latch
---@param dict_name string
---@param key string
---@param counter integer
---@param opts resty.latch.opts?
---@return resty.latch?
---@return string?
function _M.new(dict_name, key, counter, opts)
    if type(dict_name) ~= "string" then
        return nil, "invalid dictionary"
    end
    if type(key) ~= "string" then
        return nil, "invalid key"
    end
    if type(counter) ~= "number" then
        return nil, "invalid counter"
    end

    local dict = ngx.shared[dict_name]
    if not dict then
        return nil, "dictionary not found"
    end

    local exptime = opts and opts.exptime or 30

    local ok, err = dict:safe_add(key, counter, exptime)
    if not ok and err ~= "exists" then
        return nil, err
    end

    -- handler when exists if the value is zero
    if err == 'exists' then
        local old_counter = dict:get(key)
        if old_counter ~= 0 then
            return nil, err
        end
        ok, err = dict:set(key, counter, exptime)
        if not ok then
            return nil, err
        end
        assert(dict:get(key) == counter)
    end

    ---@class resty.latch
    local self = {
        dict = dict,
        key = key,
        counter = counter,
        timeout = opts and opts.timeout or 5,
        step = opts and opts.step or 0.001,
        ratio = opts and opts.ratio or 2,
        max_step = opts and opts.max_step or 0.5,
    }

    self = setmetatable(self, { __index = _M })
    return self
end

---comment Blocks the calling thread until the internal counter reaches 0. If it is zero already, returns immediately.
---@param opts resty.latch.opts?
---@return boolean?
---@return string? error
function _M:wait(opts)
    local timeout = opts and opts.timeout or self.timeout
    local step = opts and opts.step or self.step
    local ratio = opts and opts.ratio or self.ratio
    local max_step = opts and opts.max_step or self.max_step

    local elapsed = 0
    while timeout > 0 do
        sleep(step)
        elapsed = elapsed + step
        timeout = timeout - step

        local value, flags_or_error = self.dict:get(self.key)
        if not value then
            return nil, flags_or_error
        end

        if value <= 0 then
            assert(value == 0, "negative counter value:" .. value)
            return true
        end

        if timeout <= 0 then
            break
        end
        step = min(max(0.001, step * ratio), timeout, max_step)
    end
    return false, 'timeout'
end

---comment Returns true if the internal counter equals zero.
function _M:is_ready()
    local value, flags_or_error = self.dict:get(self.key)
    if type(flags_or_error) == "string" then
        return false, flags_or_error
    end
    return value == 0
end

---comment Atomically decrements the internal counter by `n` without blocking the caller.
---If `n` is greater than the value of the internal counter or is negative, the behavior is undefined.
---This operation synchronizes with all calls that block on this latch and all is_ready calls on this latch that returns true.
---comment
---@param n integer?	the value by which the internal counter is decreased
function _M:count_down(n)
    n = n or 1
    n = -n
    local value, err = self.dict:incr(self.key, n)
    if not value then
        return nil, err
    end
    assert(type(value) == "number", type(value))
    assert(value >= 0, value)
    return value
end

---Atomically decrements the internal counter by `1` and (if necessary) blocks the calling thread until the counter reaches zero.
---The behavior is undefined if the internal counter is already zero.
---This operation synchronizes with all calls that block on this latch and all is_ready calls on this latch that returns true.
---@param n integer?	the value by which the internal counter is decreased
---@param opts resty.latch.opts?
function _M:count_down_and_wait(n, opts)
    local _, err = self:count_down(n)
    if err then
        return false, err
    end
    return self:wait(opts)
end

return _M
