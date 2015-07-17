-- Copyright (C) 2015 Lloyd Zhou

local http, parser, lock = require "resty.http", require "redis.parser", require "resty.lock"

local _M = { _VERSION = '0.2'  }
local mt = {__index = _M}
local loglevel = ngx.ERR
local stuf, off = "_", "off"

function _M.new(_, o)
    local self, default = {}, {cache_lock=stuf, cache_ttl=stuf, cache_key=stuf,
        cache_persist=off,
        cache_stale=100, cache_locktime=30, cache_skip_fetch='X-Skip-Fetch'}
    for k,v in pairs(default) do
        self[k] = o[k] and (string.find(o[k], "^(%d+)$") and tonumber(o[k]) or o[k]) or v
        if stuf == self[k] then
            ngx.log(loglevel, "missing option name: ", k)
        end
    end
    return setmetatable(self, mt)
end
function _M.run(self)
    local skip = ngx.var[self.cache_skip_fetch:lower():gsub("-", "_")]
    local uri = string.gsub(ngx.var.request_uri, "?.*", "")
    if skip or self.cache_ttl == uri or self.cache_persist == uri then return end
    local key, method, stale = self.cache_key, ngx.var.request_method, self.cache_stale
    local res = ngx.location.capture(self.cache_ttl, { args={key=key}})
    local ttl = parser.parse_reply(res.body)
    ngx.log(loglevel, "[LUA], cache key", key, ", ttl: ", ttl)
    -- stale time, need update the cache
    if ttl < stale then
        -- cache missing, no need to using srcache_fetch, go to backend server, and store new cache
        -- if redis server version is 2.8- can not return -2 !!!!!!
        if ttl > -2 then
            -- option: remove expire time for key
            if self.cache_persist ~= off and ttl > 0 then
                ngx.location.capture(self.cache_persist, { args={ key=key } })
            end
            -- get a lock, if success, do not fetch cache, create new one, the lock will release in "exptime".
            -- if can not get the lock, just using the stale data from redis.
            local l = lock:new(self.cache_lock, {exptime=self.cache_locktime, timeout=0.01})
            if l and l:lock(key) then
                local func = function(p, http, uri, method, headers, body)
                    headers[self.cache_skip_fetch] = "TRUE" -- set header force to create new cache.
                    http:new():request({ url="http://127.0.0.1" .. uri, method=method, headers=headers, body=body})
                    ngx.log(loglevel, "[LUA], success to update new cache, uri: ", uri, ", method: ", method)
                end
                -- run a backend task, to update new cache
                if method == "POST" or method == "PUT" then ngx.req.read_body() end
                ngx.timer.at(0, func, http, ngx.var.request_uri, method, ngx.req.get_headers(), ngx.req.get_body_data())
            end
        end
    end
end

if ngx.var.cache_lock and ngx.var.cache_ttl and ngx.var.cache_key then
    _M.new(nil, ngx.var):run()
end
return _M

