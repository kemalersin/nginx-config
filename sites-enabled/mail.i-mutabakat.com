proxy_cache_path                    /etc/nginx/cache/iml/ use_temp_path=off levels=1:2 keys_zone=iml-cache:8m max_size=512m inactive=24h;

upstream backend_iml {
        server                      postal:5000 max_fails=3 fail_timeout=5s;
        zone                        backend_iml 128k;
        keepalive                   16;
}

server {
        listen                      80;
        server_name                 mail.i-mutabakat.com;
        server_tokens               off;
        return                      301 https://mail.i-mutabakat.com$request_uri;
}

server {
        listen                      443 ssl http2;
        server_name                 mail.i-mutabakat.com;
        server_tokens               off;

        # SSL
        ssl_certificate             /etc/nginx/ssl/mail.i-mutabakat.com/certificate.crt;
        ssl_certificate_key         /etc/nginx/ssl/mail.i-mutabakat.com/private.key;
        ssl_prefer_server_ciphers   on;
        ssl_session_cache           shared:SSL:20m;

        # logs
        #access_log                  /var/log/nginx/iml_access.log;
        #error_log                   /var/log/nginx/iml_error.log;

        gzip off;

        allow all;
        satisfy any;

        # The apache container or CloudFlare seems to add these
        #add_header                 X-Content-Type-Options nosniff;
        #add_header                 X-XSS-Protection "1; mode=block";
        #add_header                 X-Robots-Tag none;
        #add_header                 X-Download-Options noopen;
        #add_header                 X-Permitted-Cross-Domain-Policies none;

        location / {
                client_body_timeout             5m;
                client_max_body_size            10m;
                proxy_buffering                 off;
                proxy_cache                     iml-cache;
                proxy_cache_valid               200 302 30m;
                proxy_cache_valid               404 1m;
                proxy_http_version              1.1;
                proxy_pass                      http://backend_iml;
                proxy_pass_header               Authorization;
                proxy_read_timeout              30s;
                proxy_redirect                  off;
                proxy_request_buffering         off;
                proxy_set_header                Connection "";
                proxy_set_header                Host $host;
                proxy_set_header                X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header                X-Real-IP  $remote_addr;
        }
}
