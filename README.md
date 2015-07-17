# lua-resty-cache
one lua library to work with srcache, can server stale response, and using "lua-resty-lock" only allow one request to populate a new cache.

1. if the cache is missing, skip the srcache_fetch, and using lua-resty-lock to make one request to populate a new cache. the other request just wait the cache and using this new cache send to client.
2. always set the redis expires to (real expires time + stale time), so can find the stale data from reids.
3. if get stale data from redis, just send stale data to client(using ngx.eof(), the client can close this connection.)
4. and then make subrequest to populate a new cache (using lua-resty-lock, so only one request send to backend server).


## Synopsis

    upstream www {
        server 127.0.0.1:9999;
    }
    upstream redis {
        server 127.0.0.1:6379;
        keepalive 1024;
    }
    lua_shared_dict srcache_locks 1m;
    location /api {
        set $cache_lock srcache_locks;
        set $cache_ttl /redisttl;
        set $cache_persist /redispersist;
        set $cache_key "$http_user_agent|$uri";
        set $cache_stale 100;
        set $cache_locktime 3;
        set $cache_skip_fetch "X-Skip-Fetch";
        set_escape_uri $escaped_key $cache_key;
        
        rewrite_by_lua_file /usr/local/openresty/lualib/resty/cache.lua;
        
        if ($http_x_skip_fetch != TRUE){ srcache_fetch GET /redis $cache_key;}
        srcache_store PUT /redis2 key=$escaped_key&exptime=105;
        add_header X-Cache $srcache_fetch_status;
        add_header X-Store $srcache_store_status;
        #echo hello world;
        proxy_pass http://www;
    }
    location = /redisttl {
        internal;
        set_unescape_uri $key $arg_key;
        set_md5 $key;
        redis2_query ttl $key;
        redis2_pass redis;
    }
    location = /redispersist {
        internal;
        set_unescape_uri $key $arg_key;
        set_md5 $key;
        redis2_query persist $key;
        redis2_pass redis;
    }
    location = /redis {
        internal;
        set_md5 $redis_key $args;
        redis_pass redis;
    }
    location = /redis2 {
        internal;
        set_unescape_uri $exptime $arg_exptime;
        set_unescape_uri $key $arg_key;
        set_md5 $key;
        redis2_query set $key $echo_request_body;
        redis2_query expire $key $exptime;
        redis2_pass redis;
    }
