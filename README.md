  

# mangos-docker

This repository offers all needed files to build and run Mangos Servers in a kubernetes environment. 

I'm doing this for myself, mostly, so this repo will focus on helmchart and kubernetes deployment.  


## How the repository is organized

 
Each folder is dedicated to a specific version of Mangos, inside you will find everything about this precise version (from Dockerfile to deployment files).

  
Each version currently provides 3 Docker images :


*  **mangosd**: this the world server that needs maps to work. This is the server the players will be playing on.

  

*  **realmd**: this is the login server. This is the server the players will log into.

  

*  **mysql-database**: this is the database used both by the world server and the login server.

  

**As of now, only mangostwo was edited an can be considered working.**


## How to create my own server



### Using Kubernetes

  

**!! kubernetes-deployment.yml is Outdated !!**

  

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


## Configuration

### Mysql

| Parameter |Description | Default |
| -- | -- | -- |
| database | This is the database name which is used in mysql. It will also be used in the connection string. | mangos |
| databaseRealmName | The name which will be used for your realm.| Karazhan |
| dbRelease | This is the dbRelease Version for mangosDB. Rel22 is needed anyway but just in case someone wants to try other stuff | Rel22|
| image.repository| You have to bring your own images and therefore this parameter. Dockerfiles are provided in this repo, so you can create your own images without a problem. | nil|
| persistentVolume.enabled| This enabled the usage of an persistent volume. You can run the server without it, but I recommend using persistent volume for your database data | false|
| persistentVolume.existingClaimName| The name of your PVC for your MySQL or MariaDB. Note: You have to create the PVs and PVCs before applying the helmchart. | nil|


### Realmd

  

| Parameter | Description | Default |
|--|--|--|
| image.repository| You have to bring your own images and therefore this parameter. Dockerfiles are provided in this repo, so you can create your own images without a problem | nil|
| initContainer.enabled| This is a hardcoded initContainer which waits till it can netcat the created Database-service on port 3306| false|
| persistentVolume.enabled| This enabled the usage of an persistent volume. You can run the server without it, but after a crash or pod restart the data is gone! | false|
| persistentVolume.existingClaimName| The name of your PVC for your Realmd | nil|
| service.type| The Type of your service for realmd | NodePort|
| service.port| The external port for your service to listen on. | 3724|

  

### World

| Parameter | Description | Default |
|--|--|--|
| image.repository| You have to bring your own images and therefore this parameter | nil|
| initContainer.enabled| This is a hardcoded initContainer which waits till it can netcat the created Database-service on port 3306 and the realmd port on 3724.| false|
| persistentVolume.enabled| This enabled the usage of an persistent volume. You can run the server without it, but after a crash or pod restart the data is gone. Though not as bad as loosing your database data, world still contains informations like mangosd.conf and ahbot.conf | false|
| persistentVolume.Serverdata.existingClaimName| This PV serves for the entire Serverdata. You can optionally put your mapfiles beforehand on this PV (or disable map usage in config). The delievered Dockerfiles create the whole server in /var/etc/mangos and copy it to the PV mounted on /etc/mangos. I did this because the map files are far bigger than the entire world server created (without them). So it's faster to copy just the worldserver data to the PV. | nil|
| persistentVolume.configdata.existingClaimName| This the PV where the used configdata will be in. The configfiles will be copied to /tmp in launch_mangosd.sh which is the mounted PV | nil|

  

## What about the maps?

  

### Using Kubernetes

  

The Dockerfile for mangosd creates the serverfiles in /var/etc/mangos and will later copy them to /etc/mangos via launch_mangosd.sh

  

As of now the solution is as follows:

Create a physical volume and place the mapfiles in there. The values.yml has an option to mount that PV to /etc/mangos in the world container. The launch_mangosd.sh will then also copy the serverfiles to /etc/mangos, leaving you with the entire /etc/mangos on a PV

  

  

## Contributing

  

Feel free to create any issue or pull-request.
