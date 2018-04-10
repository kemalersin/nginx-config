upstream backend_cl {
        server                  collabora:9980 max_fails=3 fail_timeout=5s;
        keepalive               64;
}

proxy_cache_path                /etc/nginx/cache/cl/ use_temp_path=on levels=1:2 keys_zone=cl-cache:8m max_size=1g inactive=48h;

server {
    listen                      80;
    server_name                 collabora.kemalersin.com;
    include                     conf.d/network-whitelist-cf-mon.conf;
    return                      302 $host$request_uri;
}

server {
    listen                      443 ssl http2;
    server_name                 collabora.kemalersin.com;

    include                     conf.d/network-whitelist-cloudflare.conf;
    # SSL
    ssl_certificate             /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key         /etc/nginx/ssl/nginx.key;
    ssl_protocols               TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers                 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
    ssl_dhparam                 /etc/nginx/ssl/dhparam.pem;
    ssl_prefer_server_ciphers   on;
    ssl_session_cache           shared:SSL:20m;

    # logs
    #access_log                 /var/log/nginx/cl_access.log;
    #error_log                  /var/log/nginx/cl_error.log;

    gzip off;

    # static files
    location ^~ /loleaflet {
        proxy_pass                      https://backend_cl;
        proxy_cache                     cl-cache;
        proxy_cache_valid               200 302 60m;
        proxy_cache_valid               404 1m;
        proxy_read_timeout              60;
        proxy_connect_timeout           60;
        proxy_redirect                  off;
        proxy_set_header                Host $http_host;
    }

    # WOPI discovery URL
    location ^~ /hosting/discovery {
        proxy_pass                      https://backend_cl;
        proxy_set_header                Host $http_host;
        proxy_ssl_session_reuse         on;
    }

    # main websocket
    location ~ ^/lool/(.*)/ws$ {
        proxy_pass                      https://backend_cl;
        proxy_set_header                Upgrade $http_upgrade;
        proxy_set_header                Connection "Upgrade";
        proxy_set_header                Host $http_host;
        proxy_read_timeout              60s;
        proxy_ssl_session_reuse         on;
    }

    # download, presentation and image upload
    location ~ ^/lool {
        client_max_body_size            100m;
        client_body_timeout             30m;
        proxy_pass                      https://backend_cl;
        proxy_set_header                Host $http_host;
        proxy_ssl_session_reuse         on;
    }

    # Admin Console websocket
    location ^~ /lool/adminws {
        proxy_pass https://backend_cl;
        proxy_cache                     cl-cache;
        proxy_cache_valid               200 302 60m;
        proxy_cache_valid               404 1m;
        proxy_read_timeout              60;
        proxy_connect_timeout           60;
        proxy_redirect                  off;
        proxy_set_header                Upgrade $http_upgrade;
        proxy_set_header                Connection "Upgrade";
        proxy_set_header                Host $http_host;
        proxy_ssl_session_reuse         on;
    }
}
