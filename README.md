# edgerouter-acme

Get valid certificates for your EdgeRouter appliance!

Designed for use with an internal ACME endpoints such as [Smallstep Certificates](https://github.com/smallstep/certificates), and is designed as such:

- **will** automatically renew certificates (if configured as specified below).
- **will** persist between firmware upgrades (if configured as specified below).
- **won't** take down the webgui while requesting/renewing certificates, gracefully reloads only.
- **won't** modify any firewall rules or mess with iptables.
	- Assuming that port 80 is already open on the _inside_ of the network, and that the web GUI is not disabled.
- **won't** mess with the existing system configuration.
- **won't** work on versions of EdgeOS prior to 2.0.

If you _really_ want/need to have certificates for a public domain (although you really shouldn't expose the device), use [this alternative by @hungnguyenm](https://github.com/hungnguyenm/edgemax-acme) instead.

### Install

	ssh edgerouter
	sudo mkdir /config/acme/
	sudo curl -sSLo /config/acme/renew.sh https://raw.githubusercontent.com/p3lim/edgerouter-acme/master/renew.sh
	sudo chmod 770 /config/acme/renew.sh

### Update

If the [acme.sh](https://github.com/acmesh-official/acme.sh/releases) script is updated and this script isn't, just update the `ACME_SH_VERSION` value at the top of the script, it will download the newest version by itself.

### Configuration

Run once manually

	sudo /config/acme/renew.sh -d <my-domain.com> -u <acme endpoint>

Enter configuration mode

	configure

Configure paths to certificate files

	set service gui cert-file /config/acme/ssl/cert.pem
	set service gui ca-file /config/acme/ssl/ca.crt

Configure scheduled task to renew automatically (using same arguments as when run manually)

	set system task-scheduler task acme-renew executable path /config/acme/renew.sh
	set system task-scheduler task acme-renew executable arguments '-d <my-domain.com> -u <acme endpoint>'
	set system task-scheduler task acme-renew interval 1d

Commit, save, and exit

	commit ; save ; exit
