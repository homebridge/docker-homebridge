#!/bin/bash

set -o errexit

main() {
    case $1 in
        "prepare")
            docker_prepare
            ;;
        "build")
            docker_build
            ;;
        "test")
            docker_test
            ;;
        "tag")
            docker_tag
            ;;
        "push")
            docker_push
            ;;
        "manifest-list")
            docker_manifest_list
            ;;
        *)
            echo "none of above!"
    esac
}

docker_prepare() {
    # Prepare the machine before any code installation scripts
    setup_dependencies

    # Update docker configuration to enable docker manifest command
    update_docker_configuration

    # Prepare qemu to build images other then x86_64 on travis
    prepare_qemu
}

docker_build() {
  # Build Docker image
  echo "DOCKER BUILD: Build Docker image."
  echo "DOCKER BUILD: build version -> ${BUILD_VERSION}."
  echo "DOCKER BUILD: s6 arch -> ${S6_ARCH}."
  echo "DOCKER BUILD: avahi -> ${AVAHI}."
  echo "DOCKER BUILD: docker file - ${TAG_SUFFIX}."
  echo "DOCKER BUILD: docker file - ${DOCKER_FILE}."

  docker build \
    --build-arg BUILD_REF=${TRAVIS_COMMIT} \
    --build-arg BUILD_DATE=$(date +"%Y-%m-%dT%H:%M:%SZ") \
    --build-arg BUILD_VERSION=${BUILD_VERSION} \
    --build-arg S6_ARCH=$S6_ARCH \
    --build-arg AVAHI=$AVAHI \
    --file ./${DOCKER_FILE} \
    --tag ${TARGET_IMAGE}:build-${TAG_SUFFIX} .
}

docker_test() {
  echo "DOCKER TEST: Test Docker image."
  echo "DOCKER TEST: testing image -> ${TARGET_IMAGE}:build-${TAG_SUFFIX}."

  docker run -d --rm --name=test-${TAG_SUFFIX} ${TARGET_IMAGE}:build-${TAG_SUFFIX}
  if [ $? -ne 0 ]; then
     echo "DOCKER TEST: FAILED - Docker container test-${TAG_SUFFIX} failed to start."
     exit 1
  else
     echo "DOCKER TEST: PASSED - Docker container test-${TAG_SUFFIX} succeeded to start."
  fi
}

docker_tag() {
    echo "DOCKER TAG: Tag Docker image."
    echo "DOCKER TAG: tagging image - ${TARGET_IMAGE}:build-${TAG_SUFFIX}."
    docker tag ${TARGET_IMAGE}:build-${TAG_SUFFIX} ${TARGET_IMAGE}:${BUILD_VERSION}-${TAG_SUFFIX}
}

docker_push() {
  echo "DOCKER PUSH: Push Docker image."
  echo "DOCKER PUSH: pushing - ${TARGET_IMAGE}:${BUILD_VERSION}-${TAG_SUFFIX}."
  docker push ${TARGET_IMAGE}:${BUILD_VERSION}-${TAG_SUFFIX}
}

docker_manifest_list() {
  echo "DOCKER BUILD: TARGET_IMAGE -> ${TARGET_IMAGE}."
  echo "DOCKER BUILD: build version -> ${BUILD_VERSION}."

  # Create and push manifest lists, displayed as FIFO
  echo "DOCKER MANIFEST: Create and Push docker manifest lists."
  docker_manifest_list_version

  # if build is not a beta then create and push manifest lastest
  if [[ ${BUILD_VERSION} != *"beta"* ]]; then
      echo "DOCKER MANIFEST: Create and Push docker manifest lists LATEST."
      docker_manifest_list_latest
   else
      echo "DOCKER MANIFEST: Create and Push docker manifest lists BETA."
      docker_manifest_list_beta
  fi

  docker_manifest_list_version_avahi_os_arch
  docker_manifest_list_version_no_avahi_os_arch
}

docker_manifest_list_version() {
  # Manifest Create BUILD_VERSION
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:${BUILD_VERSION}."
  docker manifest create ${TARGET_IMAGE}:${BUILD_VERSION} \
      ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-amd64 \
      ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6 \
      ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8

  # Manifest Annotate BUILD_VERSION
  docker manifest annotate ${TARGET_IMAGE}:${BUILD_VERSION} ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6 --os=linux --arch=arm --variant=v6
  docker manifest annotate ${TARGET_IMAGE}:${BUILD_VERSION} ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8 --os=linux --arch=arm64 --variant=v8

  # Manifest Push BUILD_VERSION
  docker manifest push ${TARGET_IMAGE}:${BUILD_VERSION}
}

docker_manifest_list_latest() {
  # Manifest Create latest
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:latest."
  docker manifest create ${TARGET_IMAGE}:latest \
      ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-amd64 \
      ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6 \
      ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8

  # Manifest Annotate latest
  docker manifest annotate ${TARGET_IMAGE}:latest ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6 --os=linux --arch=arm --variant=v6
  docker manifest annotate ${TARGET_IMAGE}:latest ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8 --os=linux --arch=arm64 --variant=v8

  # Manifest Push latest
  docker manifest push ${TARGET_IMAGE}:latest
}

docker_manifest_list_beta() {
  # Manifest Create beta
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:beta."
  docker manifest create ${TARGET_IMAGE}:beta \
      ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-amd64 \
      ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6 \
      ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8

  # Manifest Annotate beta
  docker manifest annotate ${TARGET_IMAGE}:beta ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6 --os=linux --arch=arm --variant=v6
  docker manifest annotate ${TARGET_IMAGE}:beta ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8 --os=linux --arch=arm64 --variant=v8

  # Manifest Push beta
  docker manifest push ${TARGET_IMAGE}:beta
}

docker_manifest_list_version_avahi_os_arch() {
  # Manifest Create alpine-amd64
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-amd64."
  docker manifest create ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-amd64 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-amd64

  # Manifest Push alpine-amd64
  docker manifest push ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-amd64


  # Manifest Create debian-amd64
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:${BUILD_VERSION}-debian-amd64."
  docker manifest create ${TARGET_IMAGE}:${BUILD_VERSION}-debian-amd64 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-debian-amd64

  # Manifest Push debian-amd64
  docker manifest push ${TARGET_IMAGE}:${BUILD_VERSION}-debian-amd64


  # Manifest Create alpine-arm32v6
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6."
  docker manifest create ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6

  # Manifest Annotate alpine-arm32v6
  docker manifest annotate ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6 --os=linux --arch=arm --variant=v6

  # Manifest Push alpine-arm32v6
  docker manifest push ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm32v6


  # Manifest Create debian-arm32v7
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:${BUILD_VERSION}-debian-arm32v7."
  docker manifest create ${TARGET_IMAGE}:${BUILD_VERSION}-debian-arm32v7 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-debian-arm32v7

  # Manifest Annotate debian-arm32v7
  docker manifest annotate ${TARGET_IMAGE}:${BUILD_VERSION}-debian-arm32v7 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-debian-arm32v7 --os=linux --arch=arm --variant=v7

  # Manifest Push debian-arm32v7
  docker manifest push ${TARGET_IMAGE}:${BUILD_VERSION}-debian-arm32v7


  # Manifest Create alpine-arm64v8
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8."
  docker manifest create ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8

  # Manifest Annotate alpine-arm64v8
  docker manifest annotate ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8 --os=linux --arch=arm64 --variant=v8

  # Manifest Push alpine-arm64v8
  docker manifest push ${TARGET_IMAGE}:${BUILD_VERSION}-alpine-arm64v8
}

docker_manifest_list_version_no_avahi_os_arch() {
  # Manifest Create no-avahi-alpine-amd64
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-amd64."
  docker manifest create ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-amd64 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-amd64

  # Manifest Push no-avahi-alpine-amd64
  docker manifest push ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-amd64

  # Manifest Create no-avahi-debian-amd64
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-debian-amd64."
  docker manifest create ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-debian-amd64 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-debian-amd64

  # Manifest Push no-avahi-debian-amd64
  docker manifest push ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-debian-amd64

  # Manifest Create no-avahi-alpine-arm32v6
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm32v6."
  docker manifest create ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm32v6 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm32v6

  # Manifest Annotate no-avahi-alpine-arm32v6
  docker manifest annotate ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm32v6 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm32v6 --os=linux --arch=arm --variant=v6

  # Manifest Push no-avahi-alpine-arm32v6
  docker manifest push ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm32v6

  # Manifest Create no-avahi-debian-arm32v7
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-debian-arm32v7."
  docker manifest create ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-debian-arm32v7 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-debian-arm32v7

  # Manifest Annotate no-avahi-debian-arm32v7
  docker manifest annotate ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-debian-arm32v7 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-debian-arm32v7 --os=linux --arch=arm --variant=v7

  # Manifest Push no-avahi-debian-arm32v7
  docker manifest push ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-debian-arm32v7

  # Manifest Create no-avahi-alpine-arm64v8
  echo "DOCKER MANIFEST: Create and Push docker manifest list - ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm64v8."
  docker manifest create ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm64v8 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm64v8

  # Manifest Annotate no-avahi-alpine-arm64v8
  docker manifest annotate ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm64v8 \
    ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm64v8 --os=linux --arch=arm64 --variant=v8

  # Manifest Push no-avahi-alpine-arm64v8
  docker manifest push ${TARGET_IMAGE}:${BUILD_VERSION}-no-avahi-alpine-arm64v8
}

setup_dependencies() {
  echo "PREPARE: Setting up dependencies."

  sudo apt update -y
  # sudo apt install realpath python python-pip -y
  sudo apt install --only-upgrade docker-ce -y
}

update_docker_configuration() {
  echo "PREPARE: Updating docker configuration"

  mkdir $HOME/.docker

  # enable experimental to use docker manifest command
  echo '{
    "experimental": "enabled"
  }' | tee $HOME/.docker/config.json

  # enable experimental
  echo '{
    "experimental": true,
    "storage-driver": "overlay2",
    "max-concurrent-downloads": 50,
    "max-concurrent-uploads": 50
  }' | sudo tee /etc/docker/daemon.json

  sudo service docker restart
}

prepare_qemu(){
    echo "PREPARE: Qemu"
    # Prepare qemu to build non amd64 / x86_64 images
    sudo apt-get --yes --no-install-recommends install binfmt-support qemu-user-static
    docker run --rm --privileged multiarch/qemu-user-static:register --reset
}

main $1
