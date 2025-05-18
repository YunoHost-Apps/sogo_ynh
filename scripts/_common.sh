#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================

readonly time_zone=$(timedatectl show --value --property=Timezone)
# Note we can't use the upstream version helper as this version depends of the Debian package not this package and the value could differ depending of the Debian version
readonly current_sogo_version="$(dpkg-query --show --showformat='${Version}' sogo | cut -d- -f1)"

config_nginx() {
    nginx_config="/etc/nginx/conf.d/$domain.d/$app.conf"

    # shellcheck disable=SC2016
    principals_block='
# For IOS 7
location = /principals/ {
    rewrite ^ https://$server_name/SOGo/dav;
    allow all;
}'
    # shellcheck disable=SC2016
    activesync_block='
# For ActiveSync
location ^~ /Microsoft-Server-ActiveSync {
    proxy_connect_timeout 75;
    proxy_send_timeout 3600;
    proxy_read_timeout 3600;
    proxy_buffers 64 256k;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    proxy_pass http://127.0.0.1:'"$port"'/SOGo/Microsoft-Server-ActiveSync;
}'
    # shellcheck disable=SC2016
    caldav_block='
# For Caldav
location = /.well-known/caldav {
    rewrite ^ https://$server_name/SOGo/dav/;
}'
    # shellcheck disable=SC2016
    carddav_block='
# For Carddav
location = /.well-known/carddav {
    rewrite ^ https://$server_name/SOGo/dav/;
}'

    ynh_config_add_nginx

    if ! is_url_handled -d "$domain" -p "/principals"; then
        echo "$principals_block" >> "$nginx_config"
    fi
    if ! is_url_handled -d "$domain" -p "/Microsoft-Server-ActiveSync"; then
        echo "$activesync_block" >> "$nginx_config"
    fi
    if ! is_url_handled -d "$domain" -p "/.well-known/caldav"; then
        echo "$caldav_block" >> "$nginx_config"
    fi
    if ! is_url_handled -d "$domain" -p "/.wellk-nown/carddav"; then
        echo "$carddav_block" >> "$nginx_config"
    fi
    ynh_store_file_checksum "$nginx_config"
    systemctl reload nginx.service
}

set_permissions() {
    chown -R "$app:$app" "/etc/$app"
    chmod -R u=rwX,g=rX,o= "/etc/$app"

    chown -R "$app:$app" "/var/log/$app"
    chmod -R u=rwX,g=rX,o= "/var/log/$app"

    chown root: "/etc/cron.d/$app"
    chmod 644 "/etc/cron.d/$app"
}

is_url_handled() {
    # Declare an array to define the options of this helper.
    declare -Ar args_array=( [d]=domain= [p]=path= )
    local domain
    local path
    # Manage arguments with getopts
    ynh_handle_getopts_args "$@"

    # Try to get the url with curl, and keep the http code and an eventual redirection url.
    local curl_output="$(curl --insecure --silent --output /dev/null \
      --write-out '%{http_code};%{redirect_url}' https://127.0.0.1"$path" --header "Host: $domain" --resolve "$domain":443:127.0.0.1)"

    # Cut the output and keep only the first part to keep the http code
    local http_code="${curl_output%%;*}"
    # Do the same thing but keep the second part, the redirection url
    local redirection="${curl_output#*;}"

    # Return 1 if the url isn't handled.
    # Which means either curl got a 404 (or the admin) or the sso.
    # A handled url should redirect to a publicly accessible url.
    # Return 1 if the url has returned 404
    if [ "$http_code" = "404" ] || [[ "$redirection" =~ "/yunohost/admin" ]]; then
        return 1
    # Return 1 if the url is redirected to the SSO
    elif [[ "$redirection" =~ "/yunohost/sso" ]]; then
        return 1
    fi
}

handle_migration_if_needed() {
    if dpkg --compare-versions "$current_sogo_version" gt 5.8.0; then
        ynh_print_warn "Currently a SOGo version > 5.8.0 is not supported by this package. Use it at your own risk."
    fi
    if [ "$current_sogo_version" != "$previous_sogo_version" ]; then
        # Migration from 5.0.1 -> 5.8.0
        if dpkg --compare-versions "$previous_sogo_version" lt 5.8.0; then
            ynh_mysql_db_shell <<< 'DROP TABLE IF EXISTS sogo_sessions_folder;'
        fi
    fi
}

check_hostfile_configuration() {
    if grep -qF "." /etc/hostname; then
        ynh_print_warn "Your file /etc/hostname should contains only the short hostname, not the FQDN. Having the FQDN (full hostname) in '/etc/hostname' will break the feature of this application and is not recommended. See https://github.com/YunoHost/issues/issues/2460 for more details."
    fi
}
