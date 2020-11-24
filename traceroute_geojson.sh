#!/bin/bash

#
# Created on Sun Nov 22 2020
#
# The MIT License (MIT)
# Copyright (c) 2020 Liu Chun Yang   yjdwbj@gmail.com
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software
# and associated documentation files (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial
# portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
# TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#


function _check_tools(){
    _isOK=0
    if [ ! -x $MTR ]; then
        echo "$mtr 不存在"
        _isOK=1
    fi

    # if [ ! -f $MMDB ]; then
    #     echo "$MMDB 不存在"
    #     _isOK=1
    # fi

    if [ ! -x $MLOOKUP ]; then
        echo "$MLOOKUP 不存在"
        _isOK=1
    fi


    if [ $_isOK -eq 1 ]; then
        exit;
    fi 
}

function _trace_route(){
    # 不知为何，这???在bash里是一个变量。
    echo "开始测试： $HOSTIP"
    $MTR $MTR_ARGS -c $COUNT $HOSTIP | sed 's/"host": "???"/"host": "xxx"/' >  $RFILE 
    # https://programminghistorian.org/en/lessons/json-and-jq#the-array-operator-
    # https://kaijento.github.io/2017/03/26/json-parsing-jq-simplifying-with-map/
    # https://sher-chowdhury.medium.com/working-with-json-using-jq-ce06bae5545a
    # https://www.baeldung.com/linux/jq-command-json
    # https://github.com/stedolan/jq/wiki/Cookbook


    # 这里先把内容读进变量，不能直接操作文件。就是把IP的坐标信息再合并到每一个结点信息中去。
    JSON_DATA=`jq -r '.report' $RFILE`
    echo "read json data is  $JSON_DATA"
    for k in $(jq '.report.hubs | keys | .[]' $RFILE); 
    do  
        _value=$(jq -r ".report.hubs[$k]" $RFILE)
        _asn=$(jq -r ".ASN" <<< "$_value")
        _host=$(jq -r ".host" <<< "$_value")
        # ASN查不到，且地址是IPv4内网地址。
        if [[ "$_asn" == "AS???" && ($_host =~ ^(192\.168|10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.) || "$_host" == "xxx")]];then
            echo "局部路由节： $_host"
            continue
        fi 
        if [ "$_host" != "xxx" ]; then
            # 如果_host中间有空格，表示有两段，FQDN域名 (ip地址)
            if [[ $_host == *\ * ]]; then
              _host=$(echo $_host | awk '{print $2}' | sed  's/[()]//g') 
            fi
            # 如果_host不是IPv4,也不是IPv6,那就是一个域名。
            if [[ $_host == *[g-z\-]* ]]; then
                # 在现在这种IPv4和IPV6混用的情况下,使用AAAA的选项查询主机的IPv6 AAAA记录
                _host=$(dig $_host AAAA +short)
            fi
            case $GEOIP_LOOKUP in
                local)
                    # 合并两行为一行：sed  'N;s/\n/ /'
                    # sed 除去一些如：<dobule> <utf8_string>,再去掉最后一个豆号，它就是json内容了。
                    DB_RES=$(mmdblookup --file $MMDB --ip $_host location)
                    GEOTEXT=$(echo $DB_RES | sed 's/<[0-9a-z_]*>/,/g' | tr -d '\n' | sed -E  's/(.*),/\1/')
                    ;;
                network)
                    # 把lon换成了longitude,lat换成了latitude,as换成了ASN.
                    GEOTEXT=$(curl -s $IP_API/$_host | jq '. + {longitude :.lon} | . + {latitude :.lat} | . + {time_zone:.timezone } |. + {ASN:.as} | del(.lat,.lon,.as,.timezone)')
                    ;;
            esac
        fi

       
        # 把新的kv加入对应的数组对像中去。

        TMP=$(echo $JSON_DATA | jq ".hubs[$k] |= . + $GEOTEXT")
        # 替换变量里的内容。
        JSON_DATA=$TMP
    done
    # 这里再把修改后变量内容重定向到一个文件。
    echo $JSON_DATA | jq '.' | tee $_host.json
     # 除去longitude为空的结点，把负西经改成正数处理。但是在边界值画线时，平面与球还是会有
    GEOTEXT=$(echo $JSON_DATA |jq '[.hubs[] | select(.longitude!=null)] | map(.longitude = if .longitude < 0 then 180+(180 + .longitude) else .longitude end)')
    # GEOTEXT=$(echo $JSON_DATA |jq '[.hubs[] | select(.longitude!=null)]')
    JSON_DATA=$(echo $JSON_DATA | jq ".hubs = $GEOTEXT" )

}


function _create_geojson(){
    # https://developers.google.com/maps/documentation/javascript/earthquakes
    # https://wiki.openstreetmap.org/wiki/GeoJSON
    # https://doublebyteblog.wordpress.com/2014/12/03/json-to-geojson-with-jq/
    # 校验GeoJson格式 https://geojsonlint.com/
    # 在线地图测试 https://geojson.io/#map=2/32.0/-3.9

    # 转换成GeoJson,它的格式如下。
    # {
    #   "type": "Feature",
    #   "geometry": {
    #     "type": "Point",
    #     "coordinates": [125.6, 10.1]
    #   },
    #   "properties": {
    #     "name": "Dinagat Islands"
    #   }
    # }

    GEOJSON=$(echo '{"type":"FeatureCollection","features": [] }' | jq '.' )
    # 生成线段信息。
    _coordinates=$(echo $JSON_DATA | jq '.hubs | map([.longitude,.latitude])')
    LINEARR=$(echo $JSON_DATA | jq '.| {"type":"Feature","geometry":{"type":"LineString","coordinates":null},"properties":{"name":.mtr.dst, "id":.mtr.tests}}')
    LINEARR=$(echo $LINEARR | jq ".geometry.coordinates = $_coordinates")
    # 清除[null,null],再清除[]
    # LINEARR=$(echo $LINES | jq  'del(.geometry.coordinates[][] | nulls)' | jq 'del(.geometry.coordinates[] | select(length==0))')
    # 生成坐标信息。
    POINTS=$(echo $JSON_DATA | jq '.hubs | map({"type":"Feature","geometry":{"type":"Point","coordinates":[.longitude,.latitude]},"properties":{"name":.host, "id":.count,"timezone": .time_zone,"ASN":.ASN}})')
    GEOJSON=$(echo $GEOJSON | jq ".features |= . + [$LINEARR,$POINTS[]]")
    # 转换成网络请求的百分比数据格式,uri_escape。
    URI_DATA=$(echo $GEOJSON | jq -sRr @uri)
    echo $GEOJSON | jq '.' > $GFILE
    rm $RFILE
    # 打开网页提交数据。
    $OPEN $DOMAIN/#data=data:application/json,$URI_DATA
}

function _create_kml(){
    $O2O -f KML $KFILE $GFILE
}


MTR="/usr/bin/mtr"
MMDB="./GeoLite2-City.mmdb"
# 在线查询IP的地址。
IP_API='http://ip-api.com/json/' # 或者 https://ipapi.co/1.1.1.1/json/
MLOOKUP="/usr/bin/mmdblookup"
O2O="/usr/bin/ogr2ogr"
CURL="/usr/bin/curl"
RFILE="./traceroute.json"
KFILE=''
DOMAIN='http://geojson.io'
HOSTIP='1.1.1.1'
GFILE="geojson_$HOSTIP.json"
GEOIP_LOOKUP='local' # network
COUNT=10
MTR_ARGS='-y 2 -nzbj'



if (uname | grep -q 'Darwin'); then
    OPEN='open'
else
    OPEN='xdg-open'
fi

while (( $# )); do
    case $1 in
        # 这里可以完善更多的参数。
        --help|-h) 
            echo "请输入一个IP地址："
            echo "-c NUM  ping的次数"
            echo "--domain  打开GeoJson的网站,默认是 $DOMAIN"
            echo "--kml 输出KML文件"
            echo "-l 本地查找mmdb数据库"
            echo "-n 在线通过$IP_API查找"
            echo "-T 使用TCP ping."
            echo "例如：   $0 1.1.1.1"
            exit
            ;;
        --print) OPEN='echo';;
        -T)
          MTR_ARGS=${MTR_ARGS}"T"
          ;;
        -l)
            if [ ! -f $MMDB ]; then
                echo "$MMDB 不存在"
                exit
            fi
            GEOIP_LOOKUP="local"
            ;;
        -n)
            if [ ! -x $CURL ]; then
                echo "$CURL 不存在"
                exit
            fi
            GEOIP_LOOKUP="network"
            ;;
        --kml)
            shift
            KFILE=$1
            if [ ! -x "$O2O" ]; then
                echo "$O2O 不存在，无法转换"
                exit;
            fi
            ;;
        -c)
        shift
        COUNT=$1
        ;;
        --domain=*) 
        DOMAIN=$(echo $arg | cut -c 10-)
        shift
        ;;
        *) 
        HOSTIP=$1
        GFILE="geojson_$HOSTIP.json"
        ;;
    esac
    shift
done

_check_tools
# 传参：把$1传给_trace_route,在函数内的局部$1。
_trace_route 
_create_geojson
if [ ! -z $KFILE ]; then
    _create_kml
fi