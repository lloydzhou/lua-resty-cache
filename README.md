# lua-resty-cache
http cache to redis, can server stale response, and using "lua-resty-lock" only allow one request to populate a new cache

1. if the cache is missing, using lua-resty-lock to make one request to populate a new cache. the other request just wait the cache and using this new cache send to client.
2. always set the redis expires to (real expires time + stale time), so can find the stale data from reids.
3. if get stale data from redis, just send stale data to client(using ngx.eof(), the client can close this connection.)
4. and then make subrequest to populate a new cache (using lua-resty-lock, so only one request send to backend server).


## Synopsis

    lua_shared_dict cache_locks 1m;
    location / {
        set_md5 $key $http_user_agent|$request_uri;
        content_by_lua '
            require("resty.cache"):new("cache_locks", "/redis", "/fallback", nil, nil, 10, 10, "X-Cache"):run(ngx.var.key)
        ';
    }

    location /fallback {
        rewrite ^/fallback/(.*) /$1 break;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_redirect off;

        # send request to the backend
        proxy_pass http://127.0.0.1:9999;
        #echo hello world!!!;
    }

    location /redis {
        internal;
        default_type text/html;
        # number of redis commands
        set_unescape_uri $n $arg_n;
        # we need to read body explicitly here...or $echo_request_body will evaluate to empty ("")
        echo_read_request_body;
        redis2_raw_queries $n "$echo_request_body\r\n";
        redis2_connect_timeout 200ms;
        redis2_send_timeout 200ms;
        redis2_read_timeout 200ms;
        redis2_pass 127.0.0.1:6379;
        error_page 500 501 502 503 504 505 @empty_string;
    }
    location @empty_string {echo "";}
