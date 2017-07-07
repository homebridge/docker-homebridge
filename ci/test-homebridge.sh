#!/usr/bin/env bats

setup() {
  docker run --name homebridge -d -p 51826:51826 homebridge
  sleep 20
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
  sleep 20
  run testCmd
  [ "$status" -eq 0 ]
}

@test "test homebridge starts after being killed" {
  docker kill homebridge
  docker start homebridge
  sleep 20
  run testCmd
  [ "$status" -eq 0 ]
}
