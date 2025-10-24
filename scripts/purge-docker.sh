#!/bin/sh

# Stop and remove all containers
CONTAINERS=$(docker ps -a -q)
[ -n "$CONTAINERS" ] && docker stop $CONTAINERS && docker rm $CONTAINERS

# Remove all images
IMAGES=$(docker images -a -q)
[ -n "$IMAGES" ] && docker rmi $IMAGES

# Remove all networks
docker network prune -f

# Remove all volumes
docker volume prune -f

# Remove unused data
docker system prune -f -a