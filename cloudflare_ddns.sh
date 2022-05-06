#!/bin/bash

# A bash script to update a Cloudflare DNS A record with the external IP of the source machine
# Used to provide DDNS service for my home
# Needs the DNS record pre-creating on Cloudflare
# This script can be used on network devices where using Python is not possible.

## Cloudflare authentication and zone details should be set in your environment
## Example: in /etc/profile.d/cloudflare_credentials.sh
## #!/bin/bash
## export cloudflare_auth_email=email@example.com
## export cloudflare_auth_key=foo
## export zone=example.com
## export dns_record=foo.example.com
## export healthchecks_url=cron.example.com/key/path

source /config/scripts/cloudflare_credentials.sh

set -x
function ping_healthchecks {
  curl -k -m 10 --retry 5 $healthchecks_url --data-raw "$msg"
}

# Get the current external IP address
current_ip=`curl -s -X GET https://ifconfig.co -4`
echo "Current IP is $current_ip"

record_ip=`host $dns_record 1.1.1.1 -4 -t A  | grep -o '[^ ]*$'`
if [ "$record_ip" == "$current_ip" ]; then
  msg="$dns_record is currently set to $current_ip... no changes needed!"
  echo $msg >> /var/log/messages
  ping_healthchecks $msg
  exit
fi

# get the zone id for the requested zone
zone_id=`curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone&status=active" \
  -H "X-Auth-Email: $cloudflare_auth_email" \
  -H "Authorization: Bearer $cloudflare_auth_key" \
  -H "Content-Type: application/json" | jq -r '{"result"}[] | .[0] | .id'`

echo "Zone ID for $zone is $zone_id..."

# get the dns record id
dns_record_id=`curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&name=$dns_record" \
  -H "X-Auth-Email: $cloudflare_auth_email" \
  -H "Authorization: Bearer $cloudflare_auth_key" \
  -H "Content-Type: application/json" | jq -r '{"result"}[] | .[0] | .id'`

echo "Record ID for $dns_record is $dns_record_id..."

# update the record
curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$dns_record_id" \
  -H "X-Auth-Email: $cloudflare_auth_email" \
  -H "Authorization: Bearer $cloudflare_auth_key" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"A\",\"name\":\"$dns_record\",\"content\":\"$current_ip\",\"ttl\":1,\"proxied\":false}" | jq

msg="Cloudflare DDNS updated! IP address is $current_ip"
echo $msg >> /var/log/messages
ping_healthchecks $msg
