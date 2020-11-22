# traceroute_geojson

## 介绍

`traceroute_geojson`是一个纯脚本，使用`mtr`去跟踪检测目标IP(v4/v6)的路径信息.再通过IP查询出每个节点IP的地理坐标(lon/lat)数据，再把数据生成含有点(Ponint)与线(Line)的`GeoJson`.也可以使用`ogr2ogr2`再转成`Google Earth`的`KML`文件。最终显示如下:
![traceroute_geojson.png](https://github.com/yjdwbj/traceroute_geojson/blob/main/traceroute_geojson.png)



## 依赖软件 

    * mtr
    * curl
    * ogr2ogr
    * jq
    * GeoLite2-City.mmdb
    * [http://geojson.io](http://geojson.io)
    * [http://ip-api.com/json](http://ip-api.com/json)
