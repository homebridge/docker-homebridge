#!/usr/bin/env bats

setup() {
  docker run --name homebridge -d -p 51826:51826 homebridge
  sleep 15
}

teardown() {
  docker rm -f homebridge
}

testCmd() {
  curl -I http://localhost:51826/accessories \
    && docker exec homebridge pidof avahi-daemon \
    && docker exec homebridge pidof dbus-daemon \
    && docker exec homebridge pidof homebridge
}

@test "test homebridge starts" {
  run testCmd
  [ "$status" -eq 0 ]
}

@test "test homebridge starts after a graceful restart" {
  docker restart homebridge
  sleep 15
  run testCmd
  [ "$status" -eq 0 ]
}

@test "test homebridge starts after being killed" {
  docker kill homebridge
  docker start homebridge
  sleep 15
  run testCmd
  [ "$status" -eq 0 ]
}

@test "test container exits when homebridge process stops" {
  docker exec homebridge pkill homebridge
  sleep 10
  run docker exec homebridge echo "This should fail."
  [ "$status" -ne 0 ]
}

@test "test extra packages are installed" {
  docker rm -f homebridge
  docker run --name homebridge -d -e "PACKAGES=ffmpeg,openssh" homebridge
  sleep 30
  run docker exec homebridge ffmpeg -h
  [ "$status" -eq 0 ]
}
