
# mangos-docker

This repository lists everything needed to build and run Docker images for Mangos project.

## How the repository is organized

Each folder is dedicated to a specific version of Mangos, inside you will find everything about this precise version (from Dockerfile to deployment files).

Each version currently provides 3 Docker images :

*  **mangosd**: this the world server that needs maps to work. This is the server the players will be playing on.

*  **realmd**: this is the login server. This is the server the players will log into.

*  **mysql-database**: this is the database used both by the world server and the login server.

**As of now, only mangostwo was edited an can be considered working.**
  
## How to build the Docker images

Each image is self-sufficient, you can build it simply going into the folder of the version you wish to build and using:
```

docker build -t mytag:myversion .

```

  

## How to create my own server

### Using Kubernetes

  
**!! Kubernetes Way is Outdated !!**

I haven't worked on the kubernetes-deployment.yml yet. Only working way as of now is using helm.

Create the whole server using:

```bash

kubectl  apply  -f  kubernetes-deployment.yml

```

Passwords are kept inside the `Secret` resource.

#### Using Helm

There is a helm chart included in this repository that can be used to provide a more flexible way of deploying to Kubernetes.

  

To deploy, make any needed edits to the `values.yaml` file and apply using:

```bash

helm  install

```

## What about the maps?



### Using Kubernetes

  
The Dockerfile for mangosd creates the serverfiles in /var/etc/mangos and will later copy them to /etc/mangos via launch_mangosd.sh

As of now the solution is as follows:
Create a physical volume and place the mapfiles in there. The values.yml has an option to mount that PV to /etc/mangos in the world container. The launch_mangosd.sh will then also copy the serverfiles to /etc/mangos, leaving you with the entire /etc/mangos on a PV

## Configuration 
### Mysql
| Parameter | Description | Default |
|--|--|--|
| database  | This is the database name which is used in mysql. It will also be used in the connection string. | mangos |
| databaseRealmName | The realmname | Karazhan |
| dbRelease | This is the dbRelease Version for mangosDB. Rel22 is needed anyway but just in case someone wants to try other stuff | Rel22|
| image.repository| You have to bring your own images and therefore this parameter | nil|
| persistentVolume.enabled| This enabled the usage of an persistent volume. You can run the server without it, but after a crash or pod restart the data is gone! | false|
| persistentVolume.existingClaimName| The name of your PVC for your MySQL or MariaDB | nil|

### Realmd

| Parameter | Description | Default |
|--|--|--|
| image.repository| You have to bring your own images and therefore this parameter | nil|
| initContainer| This is a hardcoded initContainer which waits till it can netcat the created Database-service on port 3306. | nil|
| initContainer.enabled| In the end you can run without it but probably it is better to use it. In future I may work on more options of the container to be set on in the values.yaml instead of hardcodet| false|
| persistentVolume.enabled| This enabled the usage of an persistent volume. You can run the server without it, but after a crash or pod restart the data is gone! | false|
| persistentVolume.existingClaimName| The name of your PVC for your Realmd | nil|
| service.type| The Type of your service for realmd  | NodePort|
| service.port| The external port for your service to listen on.  | 3724|

  ### World
| Parameter | Description | Default |
|--|--|--|
| image.repository| You have to bring your own images and therefore this parameter | nil|
| persistentVolume.enabled| This enabled the usage of an persistent volume. You can run the server without it, but after a crash or pod restart the data is gone! | false|
| initContainer| This is a hardcoded initContainer which waits till it can netcat the created Database-service on port 3306 and the realmd port on 3724. | nil|
| initContainer.enabled| In the end you can run without it but probably it is better to use it. In future I may work on more options of the container to be set on in the values.yaml instead of hardcodet| false|
| persistentVolume.enabled| This enabled the usage of an persistent volume. You can run the server without it, but after a crash or pod restart the data is gone! | false|
| persistentVolume.Serverdata.existingClaimName| This the PV where the entire /etc/mangos path will be mounted to. You can use this PV to put the map-files in it. It will be mounted to /etc/mangos and the serverfiles will be copied there from /var/etc/mangos, which is the path used in the Dockerimage until then. | nil|
| persistentVolume.configdata.existingClaimName| This the PV where the used configdata will be in. The configfiles will be copied to /tmp which is the mounted PV | nil|

## Contributing

Feel free to create any issue or pull-request.
