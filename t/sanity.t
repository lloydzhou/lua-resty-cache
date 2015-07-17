# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 4);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_shared_dict srcache_locks 100k;
    upstream www {
        server 127.0.0.1:9999;
    }
    upstream redis {
        server 127.0.0.1:6379;
        keepalive 1024;
    }
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

no_long_string();
#no_diff();

run_tests();

__DATA__

=== TEST 1: lock is subject to garbage collection 
--- http_config eval: $::HttpConfig
--- config
    location /live/homepage {
        default_type application/json;

        set $cache_lock srcache_locks;
        set $cache_ttl /redisttl;
        set $cache_persist /redispersist;
        set $cache_key "$http_user_agent|$uri";
        set $cache_stale 100;
        set $cache_lock_exptime 30;
        set $cache_backend_lock_timeout 0.01;
        set $cache_lock_timeout 3;
        set $cache_lock_timeout_wait 0.06;
        set $cache_skip_fetch "X-Skip-Fetch";
        set_escape_uri $escaped_key $cache_key;
        rewrite_by_lua_file "../../lib/resty/cache.lua";

        if ($http_x_skip_fetch != TRUE){ srcache_fetch GET /redis $cache_key;}
        srcache_store PUT /redis2 key=$escaped_key&exptime=105;
        add_header X-Cache $srcache_fetch_status;
        add_header X-Store $srcache_store_status;
        echo hello world;
        #proxy_pass http://www;
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
--- request
GET /live/homepage
--- response_headers
X-Cache: HIT
X-Store: BYPASS
--- no_error_log
[error]


