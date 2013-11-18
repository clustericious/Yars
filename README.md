# Yars [![Build Status](https://secure.travis-ci.org/plicease/Yars.png)](http://travis-ci.org/plicease/Yars)

A REST file server built on the
Clustericious framework.

Installation on a server is as follows :

```
perl Build.PL
./Build
./Build test
./Build install
```

See eg/ for sample configurations.

The simplest configuration places all
of the md5 prefixes on one disk
on one server :

```
---
url : http://localhost:9050
servers : 
    - url : http://localhost:9050
      buckets : [0,1,2,3,4,5,6,7,8,9,A,B,C,D,E,F]
disks :
    - root : /some/place/to/put/the/files
      buckets : [0,1,2,3,4,5,6,7,8,9,A,B,C,D,E,F]
```
