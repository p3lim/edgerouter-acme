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
while getopts "d:u:ih" opt; do
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
	if ! cat <<EOF >"$ACME_DIR/lighttpd.conf"
server.pid-file = "$ACME_DIR/lighttpd.pid"
server.document-root = "$ACME_DIR/http"
server.port = 80

server.modules = ("mod_accesslog")
accesslog.filename = "$ACME_DIR/lighttpd.log"
EOF
	then
		err 'Failed to create lighttpd configuration'
	fi
}

log 'Killing webgui' ; {
	systemctl stop lighttpd || err 'Failed to stop webgui'
}

log 'Attempting renew' ; {
	"$ACME_DIR/acme.sh" \
		--issue \
		$ARG_DOMAINS \
		$ARG_SERVER \
		$ARG_INSECURE \
		--ca-file "$CERT_DIR/ca.crt" \
		--cert-file "$CERT_DIR/cert.crt" \
		--key-file "$CERT_DIR/cert.key" \
		--reloadcmd "cat $CERT_DIR/cert.key $CERT_DIR/cert.crt > $CERT_DIR/cert.pem" \
		--pre-hook "lighttpd -f $ACME_DIR/lighttpd.conf" \
		--post-hook "kill \$(cat $ACME_DIR/lighttpd.pid)" \
		--webroot "$HTTP_DIR"
}

log 'Starting webgui' ; {
	systemctl start lighttpd || err 'Failed to start webgui'
}
