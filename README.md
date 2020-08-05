# public-file-service
Microservice forked from [mu-semtech/file-service](https://github.com/mu-semtech/file-service) to download public files from Kaleidos. The service only exposes the GET endpoints of the file service and adds an additional check on the access level of the requested file. Only files with a public access level can be downloaded.

For installation, configuration and usage, see the README of [mu-semtech/file-service](https://github.com/mu-semtech/file-service).
