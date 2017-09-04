#!/bin/bash
BASEURL='http://download.maxmind.com/download/geoip/database/'
GEOLITECOUNTRY='GeoLiteCountry/GeoIP.dat.gz'
GEOLITECOUNTRYV6='GeoIPv6.dat.gz'
GEOLITECITY='GeoLiteCity.dat.gz'
GEOLITECITYV6='GeoLiteCityv6-beta/GeoLiteCityv6.dat.gz'
GEOLITEASN='asnum/GeoIPASNum.dat.gz'
GEOLITEASNV6='asnum/GeoIPASNumv6.dat.gz'

mkdir $HOME/Maxmind
cd Maxmind

# download GeoLite Country
URL="$BASEURL"
URL+="$GEOLITECOUNTRY"
wget -nc $URL
gunzip -f GeoIP.dat.gz

# download GeoLite Country IPv6
URL="$BASEURL"
URL+="$GEOLITECOUNTRYV6"
wget -nc $URL
gunzip -f GeoIPv6.dat.gz

# download GeoLite City
URL="$BASEURL"
URL+="$GEOLITECITY"
wget -nc $URL
gunzip -f GeoLiteCity.dat.gz

# download GeoLite City IPv6
URL="$BASEURL"
URL+="$GEOLITECITYV6"
wget -nc $URL
gunzip -f GeoLiteCityv6.dat.gz

# download GeoLite ASN
URL="$BASEURL"
URL+="$GEOLITEASN"
wget -nc $URL
gunzip -f GeoIPASNum.dat.gz

# download GeoLite ASN IPv6
URL="$BASEURL"
URL+="$GEOLITEASNV6"
wget -nc $URL
gunzip -f GeoIPASNumv6.dat.gz
