#!/bin/bash

ACME_SH_VERSION='2.8.6'

ACME_DIR='/config/acme'
CERT_DIR="$ACME_DIR/ssl"
HTTP_DIR="$ACME_DIR/http"

usage(){
	cat <<EOF
usage: $0 [OPTION]...

	-d  domain to request certificates for
	-u  ACME endpoint url
	-i  insecure requests, in case the ACME endpoint certificate is not known
	-f  force renewal even before the due time
	-h  display this help message and exit

The -d and -u options are required. -d can be specified multiple times.
EOF

	exit 1
}

log(){
	printf -- "%s [INFO] %s\n" "[$(date)]" "$1"
}

err(){
	printf -- "%s [ERROR] %s\n" "[$(date)]" "$1"
	exit 1
}

# parse options
while getopts "d:u:ifh" opt; do
	case "$opt" in
		d)
			DOMAINS+=("$OPTARG")
			;;
		u)
			ARG_SERVER="--server $OPTARG "
			;;
		i)
			ARG_INSECURE='--insecure '
			;;
		f)
			ARG_FORCE='--force '
			;;
		h | *)
			usage
			;;
	esac
done
shift $((OPTIND - 1))

# validate options
if [ "${#DOMAINS[@]}" -eq 0 ] || [ -z "$ARG_SERVER" ]; then
	usage
fi

# prepare flags
for domain in "${DOMAINS[@]}"; do
	if [ -z "$ARG_DOMAINS" ]; then
		ARG_DOMAINS="--domain $domain "
	else
		ARG_DOMAINS+="--domain-alias $domain "
	fi
done

log 'Creating directories' ; {
	mkdir -p "$ACME_DIR" "$CERT_DIR" "$HTTP_DIR" || err 'Failed to create directories'
}

log "Installing/updating acme.sh (v$ACME_SH_VERSION)" ; {
	curl -sSL "https://raw.githubusercontent.com/acmesh-official/acme.sh/$ACME_SH_VERSION/acme.sh" \
		-o "$ACME_DIR/acme.sh" || err 'Failed to download acme.sh'

	chmod 770 "$ACME_DIR/acme.sh" || err 'Failed to change permissions on acme.sh'
}

log 'Configuring lighttpd' ; {
	if ! /bin/grep -qxF 'include "acme.conf"' /etc/lighttpd/lighttpd.conf; then
		if ! /bin/echo 'include "acme.conf"' >> /etc/lighttpd/lighttpd.conf; then
			err 'Failed to modify webgui configuration'
		fi

		if ! /bin/cat <<EOF >/etc/lighttpd/acme.conf
\$HTTP["url"] =~ "^/.well-known/acme-challenge/" {
	\$HTTP["host"] =~ "^([^\:]+)(\:.*)?\$" {
		url.redirect = ("^/(.*)" => "http://%1:9090/\$1")
		url.redirect-code = 302
	}
}
EOF
		then
			err 'Failed to modify webgui configuration'
		fi

		mkdir -p /etc/systemd/system/lighttpd.service.d/

		if ! cat <<EOF >/etc/systemd/system/lighttpd.service.d/reload.conf
[Service]
ExecReload=/usr/bin/kill -HUP $MAINPID
EOF
		then
			err 'Failed to modify webgui service'
		fi

		systemctl daemon-reload || err 'Failed to reload systemd daemon'
		systemctl restart lighttpd || err 'Failed to restart webgui'
	fi
}

log 'Configuring challenge webserver' ; {
	if ! cat <<EOF >"$ACME_DIR/lighttpd.conf"
server.pid-file = "$ACME_DIR/lighttpd.pid"
server.document-root = "$ACME_DIR/http"
server.port = 9090

server.modules = ("mod_accesslog")
accesslog.filename = "$ACME_DIR/lighttpd.log"
EOF
	then
		err 'Failed to create lighttpd configuration'
	fi
}

log 'Attempting renew' ; {
	"$ACME_DIR/acme.sh" \
		--issue \
		$ARG_DOMAINS \
		$ARG_SERVER \
		$ARG_INSECURE \
		$ARG_FORCE \
		--ca-file "$CERT_DIR/ca.crt" \
		--cert-file "$CERT_DIR/cert.crt" \
		--key-file "$CERT_DIR/cert.key" \
		--reloadcmd "/bin/cat $CERT_DIR/cert.key $CERT_DIR/cert.crt > $CERT_DIR/cert.pem" \
		--pre-hook "/usr/sbin/lighttpd -f $ACME_DIR/lighttpd.conf" \
		--post-hook "/usr/bin/kill \$(/bin/cat $ACME_DIR/lighttpd.pid)" \
		--renew-hook '/bin/systemctl reload lighttpd' \
		--webroot "$HTTP_DIR" 2>&1
}
