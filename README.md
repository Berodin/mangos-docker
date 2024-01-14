# mangos-docker
This repository lists everything needed to build and run Docker images for Mangos project.

## How the repository is organized
Each folder is dedicated to a specific version of Mangos, inside you will find everything about this precise version (from Dockerfile to deployment files).
Each version currently provides 3 Docker images :
* **mangosd**: this the world server that needs maps to work. This is the server the players will be playing on.
* **realmd**: this is the login server. This is the server the players will log into.
* **mysql-database**: this is the database used both by the world server and the login server.

As of now, only mangostwo was edited an can be considered working.

## How to build the Docker images
Each image is self-sufficient, you can build it simply going into the folder of the version you wish to build and using:
```
docker build -t mytag:myversion .
```

## How to create my own server
### Using Kubernetes

!! Outdated !! 
I haven't worked on the kubernetes-deployment.yml yet. Only working way as of now is using helm.
Create the whole server using:
```bash
kubectl apply -f kubernetes-deployment.yml
```
Passwords are kept inside the `Secret` resource.
#### Using Helm
There is a helm chart included in this repository that can be used to provide a more flexible way of deploying to Kubernetes.

To deploy, make any needed edits to the `values.yaml` file and apply using:
```bash
helm install
```
## What about the maps?

### Using Kubernetes

The Dockerfile for mangosd creates the serverfiles in /var/etc/mangos and will later copy them to /etc/mangos via launch_mangosd.sh

The solution is to create a PV in kubernetes, add the map folders there and mount the PV to /etc/mangos in the container.

Mysql
| Parameter         | Description | Default |
| :---------------- | :------:    | ----: |
| database          |   This is the database name which is used in mysql. It will also be used in the connection string.      | mangos |
| databaseRealmName |   This is the realmname.      | Karazhan |
| dbRelease         |  This is the dbRelease Version for mangosDB. Rel22 is needed anyway but just in case someone wants to try other stuff      | Rel22 |


## Contributing
Feel free to create any issue or pull-request.
