# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

my $pwd = cwd();

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    lua_package_cpath "/usr/local/openresty-debug/lualib/?.so;/usr/local/openresty/lualib/?.so;;";
    lua_shared_dict cache_locks 100k;
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
    location = /t {
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
--- request
GET /t
--- response_headers
Content-Type: text/html; charset=UTF-8
--- no_error_log
[error]


