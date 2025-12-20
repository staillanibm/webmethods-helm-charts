#!/bin/sh
#
# Creates Universal Messaging interfaces dynamically based on parameters
# Parameters: um_host um_port um_nsp_port um_nsps_port um_nhp_port um_nhps_port
#

um_host=$1
um_port=$2
um_nsp_port=$3
um_nsps_port=$4
um_nhp_port=$5
um_nhps_port=$6

SSL_KEYSTORE="${SSL_KEYSTORE:-/opt/softwareag/common/conf/keystore.jks}"
SSL_KEYSTORE_PASS="${SSL_KEYSTORE_PASS:-changeit}"
SSL_TRUSTSTORE="${SSL_TRUSTSTORE:-/opt/softwareag/common/conf/truststore.jks}"
SSL_TRUSTSTORE_PASS="${SSL_TRUSTSTORE_PASS:-changeit}"

echo "Creating Universal Messaging interfaces..."
echo "UM Host: $um_host"
echo "UM Port: $um_port"
echo "NSP Port: $um_nsp_port"
echo "NSPS Port: $um_nsps_port"
echo "NHP Port: $um_nhp_port"
echo "NHPS Port: $um_nhps_port"

# Create NSP interface if port is provided
if [ -n "$um_nsp_port" ] && [ "$um_nsp_port" != "null" ]; then
  echo "Creating NSP interface on port $um_nsp_port..."
  runUMTool.sh AddSocketInterface -rname=nhp://localhost:$um_port -adapter=0.0.0.0 -port=$um_nsp_port -autostart=true || echo "NSP interface may already exist"
fi

# Create NSPS (SSL) interface if port is provided
if [ -n "$um_nsps_port" ] && [ "$um_nsps_port" != "null" ]; then
  echo "Creating NSPS (SSL) interface on port $um_nsps_port..."
  runUMTool.sh AddSSLInterface -rname=nhp://localhost:$um_port -adapter=0.0.0.0 -port=$um_nsps_port \
    -keystore=$SSL_KEYSTORE -kspassword=$SSL_KEYSTORE_PASS \
    -truststore=$SSL_TRUSTSTORE -tspassword=$SSL_TRUSTSTORE_PASS \
    -autostart=true || echo "NSPS interface may already exist"
fi

# Create NHP interface if port is provided and different from default
if [ -n "$um_nhp_port" ] && [ "$um_nhp_port" != "null" ] && [ "$um_nhp_port" != "$um_port" ]; then
  echo "Creating NHP interface on port $um_nhp_port..."
  runUMTool.sh AddHTTPInterface -rname=nhp://localhost:$um_port -adapter=0.0.0.0 -port=$um_nhp_port -autostart=true || echo "NHP interface may already exist"
fi

# Create NHPS (HTTPS) interface if port is provided
if [ -n "$um_nhps_port" ] && [ "$um_nhps_port" != "null" ]; then
  echo "Creating NHPS (HTTPS) interface on port $um_nhps_port..."
  runUMTool.sh AddHTTPSInterface -rname=nhp://localhost:$um_port -adapter=0.0.0.0 -port=$um_nhps_port \
    -keystore=$SSL_KEYSTORE -kspassword=$SSL_KEYSTORE_PASS \
    -truststore=$SSL_TRUSTSTORE -tspassword=$SSL_TRUSTSTORE_PASS \
    -autostart=true || echo "NHPS interface may already exist"
fi

echo "Interface creation completed."
