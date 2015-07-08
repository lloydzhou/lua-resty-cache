local parser = require "redis.parser"
local json = require "cjson"
local lock = require "resty.lock"

local _M = { _VERSION = '0.1'  }
local mt = {__index = _M}
local loglevel = ngx.NOTICE
local find = function(value, list)
    for _, v in pairs(list) do
        if v == value then return true end
    end
    return false
end
local query = function(cache, queries)
    local raw = {}
    for i, q in ipairs(queries) do
        table.insert(raw, parser.build_query(q))
    end
    local response = ngx.location.capture(cache, {method=ngx.HTTP_POST, args={n=#raw}, body=table.concat(raw, "")})
    if response.status ~= 200 or not response.body then
        ngx.log(loglevel, "[LUA] failed to query redis data")
    end
    return response
end
local out = function(status, headers, body, cache_header, cache_status)
    for n, v in pairs(headers or {}) do
        ngx.header[n] = v
    end
    if cache_header then
        ngx.header[cache_header] = cache_status or ""
    end
    ngx.status = tonumber(status)
    ngx.print(body)
    ngx.eof()
end
local cache = function(self, key, output, l)
    local response = ngx.location.capture(self.fallback .. ngx.var.request_uri)
    local store = find(response.status, self.status)
    if output then
        out(response.status, response.header, response.body, self.header, store and "STORE" or "SKIP")
    end
    if store then
        local exp_header, cache_control = response.header['Expire'], response.header['Cache-Control']
        local t = exp_header and ngx.parse_http_time(exp_header) - ngx.now()
        if cache_control then
            local _, _, _, age = string.find(cache_control, "(.*):(.*)")
            t = age and tonumber(age)
        end
        query(self.cache, {
            {"MULTI"},
            {"HMSET", key, "status", response.status, "headers", json.encode(response.header), "body", response.body},
            {"EXPIRE", key, (t or self.age) + self.stale},
            {"EXEC"}})
        ngx.log(loglevel, "[LUA] cache store on cache key: ", key)
    end
    if l then l:unlock() end
end
function get(self, key, l)
    local response = query(self.cache, {
        {"TTL", key},
        {"HGET", key, "status"},
        {"HGET", key, "headers"},
        {"HGET", key, "body"}})
    local res = parser.parse_replies(response.body, 4)
    local ttl = tonumber(res[1][1])
    if not (res == nil) and (#res == 4) and ttl > -1 then
        ngx.log(loglevel, "[LUA] cache hit on cache key: ", key, ", TTL: ", ttl)
        out(res[2][1], json.decode(res[3][1]), res[4][1], self.header, ttl <= self.stale and "STALE" or "HIT")
        if l then l:unlock() end
        if ttl < self.stale then
            ngx.log(loglevel, "[LUA] cache stale on cache key: ", key, ", TTL: ", ttl)
            l = lock:new(self.lockname, {timeout=0.01})
            if l:lock(key) then cache(self, key, false, l) end
        end
    else
        if l then cache(self, key, true, l) else
            l = lock:new(self.lockname, {timeout=3})
            if l:lock(key) then get(self, key, l) end
        end
    end
end
---------------------------------
function _M.new(_, lockname, cache, fallback, status, methods, age, stale, header)
    return setmetatable({
        lockname=lockname,
        cache=cache, fallback=fallback,
        status=status or {ngx.HTTP_OK}, methods=methods or {"GET", "HEAD"},
        age=age or 120, stale=stale or 100, header=header}, mt)
end
function _M.run(self, key)
    if find(ngx.var.request_method, self.methods) then
        get(self, key or ngx.md5(ngx.var.request_uri), nil)
    end
end

return _M

