#!/bin/bash

# Vérifier si Docker Swarm est actif
SWARM_ACTIVE=$(docker info --format '{{.Swarm.LocalNodeState}}')

if [ "$SWARM_ACTIVE" = "active" ]; then
    # Supprimer tous les services Docker Swarm
    docker service rm $(docker service ls -q)

    # Supprimer tous les stacks Docker Swarm
    docker stack rm $(docker stack ls -q)

    # Supprimer tous les secrets Docker Swarm
    docker secret rm $(docker secret ls -q)

    # Supprimer toutes les configs Docker Swarm
    docker config rm $(docker config ls -q)

    # Supprimer le swarm
    docker swarm leave --force
fi

# Supprimer tous les conteneurs
docker rm -f $(docker ps -aq)

# Supprimer toutes les images
docker rmi -f $(docker images -aq)

# Supprimer tous les volumes
docker volume rm $(docker volume ls -q)

# Supprimer tous les réseaux
docker network rm $(docker network ls -q)

echo "Docker a été réinitialisé avec succès."
