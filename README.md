pbxd
====

A server that maintains a pool of connections to a PBX and provides the XML web service API to the PBX systems.

Components
---------------
#### Connection Pool Server

The core "pbxd" part that uses PBX::DEFINITY and Net::Server::PreFork to maintain a pool of PBX connections.

#### Perl module

The underlying PBX::DEFINITY module for the server.

#### Web CGI proxy

A CGI script that handles client access control and maps request to the correct pooled server.

#### Clients

* a simple example client in perl

* pbx-export: a flexible python client that can bulk extract PBX data

Getting started
-----------------
1. install the PBX::DEFINITY perl module from pbx_lib

2. install Net::Server::PreFork from CPAN

3. install, configure and startup the connection pool server
  * each PBX needs a conf file in /etc/pbxd/ directory. The name of the conf file should be "pbxd-$pbxd_nodename.conf". The conf file needs to specify a unique port to listen on.

4. configure and install the CGI to a web server
  * you need to modify the function "lookup\_pbxd\_port" to add a mapping between the $pbxName and the port the pbxd server is listening for that PBX.

TODO
-------
* simplify and package the installation

* init.d scripts
