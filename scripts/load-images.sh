#!/bin/bash
set -e

CLUSTER_NAME="netiks"

echo "Pulling postgres directly into the kind node (bypassing Docker Desktop bug)..."
docker exec netiks-control-plane crictl pull docker.io/library/postgres:16-alpine

echo "Loading Netiks images..."
kind load docker-image netiks/identity-service:v1 --name $CLUSTER_NAME
kind load docker-image netiks/vendor-service:v1 --name $CLUSTER_NAME
kind load docker-image netiks/catalog-service:v1 --name $CLUSTER_NAME
kind load docker-image netiks/media-service:v1 --name $CLUSTER_NAME
kind load docker-image netiks/admin-service:v1 --name $CLUSTER_NAME
kind load docker-image netiks/gateway:v1 --name $CLUSTER_NAME
kind load docker-image netiks/gateway:v2 --name $CLUSTER_NAME
kind load docker-image netiks/web:v1 --name $CLUSTER_NAME

echo "All images loaded successfully!"