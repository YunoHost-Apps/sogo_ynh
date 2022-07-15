#!/bin/bash

#=================================================
# SET ALL CONSTANTS
#=================================================

# dependencies used by the app
pkg_dependencies="sogo stunnel4 memcached"

#=================================================
# DEFINE ALL COMMON FONCTIONS
#=================================================

config_stunnel() {
    ynh_add_config --template="stunnel.conf" --destination="/etc/stunnel/$app.conf"

    # Enable stunnel at startup
    ynh_replace_string --match_string "ENABLED=0" --replace_string "ENABLED=1" --target_file /etc/default/stunnel4
}

config_nginx() {
    ynh_add_nginx_config

    nginx_domain_path=/etc/nginx/conf.d/$domain.d/*
    nginx_config_path="/etc/nginx/conf.d/$domain.d/$app.conf"

    grep "/principals" $nginx_domain_path || echo "# For IOS 7
location = /principals/ {
    rewrite ^ https://\$server_name/SOGo/dav;
    allow all;
}
" >> "$nginx_config_path"

    grep "/Microsoft-Server-ActiveSync" $nginx_domain_path || echo "# For ActiveSync
location /Microsoft-Server-ActiveSync/ {
    proxy_pass http://127.0.0.1:$port/SOGo/Microsoft-Server-ActiveSync/;
}
" >> "$nginx_config_path"

    grep "/.well-known/caldav" $nginx_domain_path || echo "# For Caldav
location /.well-known/caldav {
    rewrite ^ https://\$server_name/SOGo/dav/;
}
" >> "$nginx_config_path"

    grep "/.well-known/carddav" $nginx_domain_path || echo "# For Carddav
location /.well-known/carddav {
    rewrite ^ https://\$server_name/SOGo/dav/;
}
" >> "$nginx_config_path"

    ynh_store_file_checksum --file "$nginx_config_path"

    systemctl reload nginx
}

set_permission() {
    chown -R $app:$app /etc/$app
    chmod u=rwX,g=rX,o= -R /etc/$app
    chown -R $app:$app /var/log/$app
    chmod u=rwX,g=rX,o= -R /var/log/$app
}
